import ScreenSaver
import AVFoundation
import AVKit
import QuartzCore
import CoreImage

class AustinSaverView: ScreenSaverView {

    // MARK: - Properties

    private var backgroundPlayer: AVQueuePlayer?
    private var backgroundLayer: AVPlayerLayer?
    private var overlayPlayer: AVQueuePlayer?
    private var overlayLayer: AVPlayerLayer?
    private var backgroundLooper: AVPlayerLooper?
    private var watchdogTimer: Timer?
    private var statusObservation: NSKeyValueObservation?

    private var overlayClips: [URL] = []
    private var currentOverlayIndex = 0

    // Where to find the assets
    private let effectsFolder = "AustinEffects"
    private let backgroundsFolder = "AustinBackgrounds"

    // MARK: - Lifecycle

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func startAnimation() {
        super.startAnimation()
        setupLayers()
    }

    override func stopAnimation() {
        super.stopAnimation()
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        statusObservation?.invalidate()
        statusObservation = nil
        NotificationCenter.default.removeObserver(self)
        backgroundPlayer?.pause()
        overlayPlayer?.pause()
        backgroundLayer?.removeFromSuperlayer()
        overlayLayer?.removeFromSuperlayer()
        backgroundPlayer = nil
        overlayPlayer = nil
        backgroundLayer = nil
        overlayLayer = nil
        backgroundLooper = nil
    }

    // MARK: - Setup

    private func setupLayers() {
        guard let layer = self.layer else {
            NSLog("AustinSaver: NO LAYER")
            return
        }

        layer.backgroundColor = NSColor.black.cgColor

        let assetsBase = findAssetsDirectory()
        NSLog("AustinSaver: Assets dir = \(assetsBase.path)")

        let bgVideos = findVideos(in: assetsBase.appendingPathComponent(backgroundsFolder))
        let allEffects = findVideos(in: assetsBase.appendingPathComponent(effectsFolder))

        // Filter out the pre-composited screensaver and any non-effect files
        overlayClips = allEffects.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix("_final.mp4") && !name.contains("screensaver")
        }.shuffled()

        NSLog("AustinSaver: Found \(bgVideos.count) backgrounds, \(overlayClips.count) effects (filtered from \(allEffects.count))")

        // Setup background video player
        if let bgVideo = bgVideos.randomElement() {
            NSLog("AustinSaver: Background video = \(bgVideo.lastPathComponent)")
            let bgItem = AVPlayerItem(url: bgVideo)
            let bgPlayer = AVQueuePlayer(playerItem: bgItem)
            backgroundLooper = AVPlayerLooper(player: bgPlayer, templateItem: bgItem)
            bgPlayer.isMuted = true

            let bgLayer = AVPlayerLayer(player: bgPlayer)
            bgLayer.frame = layer.bounds
            bgLayer.videoGravity = .resizeAspectFill
            bgLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer.addSublayer(bgLayer)

            self.backgroundPlayer = bgPlayer
            self.backgroundLayer = bgLayer
            bgPlayer.play()
        }

        if !overlayClips.isEmpty {
            setupNextOverlay()
        }
    }

    private func setupNextOverlay() {
        guard let layer = self.layer, !overlayClips.isEmpty else {
            NSLog("AustinSaver: setupNextOverlay guard failed - layer=\(self.layer != nil) clips=\(overlayClips.count)")
            return
        }

        // Clean up previous
        watchdogTimer?.invalidate()
        statusObservation?.invalidate()
        overlayPlayer?.pause()
        overlayLayer?.removeFromSuperlayer()
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemFailedToPlayToEndTime, object: nil)

        let clip = overlayClips[currentOverlayIndex % overlayClips.count]
        currentOverlayIndex += 1
        NSLog("AustinSaver: Playing effect #\(currentOverlayIndex): \(clip.lastPathComponent)")

        // Reshuffle when we've gone through all clips
        if currentOverlayIndex % overlayClips.count == 0 {
            overlayClips.shuffle()
            NSLog("AustinSaver: Reshuffled effects")
        }

        let item = AVPlayerItem(url: clip)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true

        let ovLayer = AVPlayerLayer(player: player)
        ovLayer.frame = layer.bounds
        ovLayer.videoGravity = .resizeAspect
        ovLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        if let filter = CIFilter(name: "CIScreenBlendMode") {
            ovLayer.compositingFilter = filter
        }

        layer.addSublayer(ovLayer)
        self.overlayPlayer = player
        self.overlayLayer = ovLayer

        // Watch for successful completion
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(overlayDidFinish(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        // Watch for playback failure
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(overlayDidFail(_:)),
            name: NSNotification.Name.AVPlayerItemFailedToPlayToEndTime,
            object: item
        )

        // Observe item status for load failures
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed {
                NSLog("AustinSaver: ERROR - Item failed to load: \(item.error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async {
                    self?.advanceToNext()
                }
            }
        }

        // Watchdog: if nothing happens in 30s, force advance
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            NSLog("AustinSaver: WATCHDOG - 30s timeout, forcing next effect")
            self?.advanceToNext()
        }

        player.play()
    }

    @objc private func overlayDidFinish(_ notification: Notification) {
        NSLog("AustinSaver: Effect completed successfully")
        advanceToNext()
    }

    @objc private func overlayDidFail(_ notification: Notification) {
        let error = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "unknown"
        NSLog("AustinSaver: ERROR - Effect failed: \(error)")
        advanceToNext()
    }

    private func advanceToNext() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        statusObservation?.invalidate()
        statusObservation = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else {
                NSLog("AustinSaver: WARN - self deallocated in advanceToNext")
                return
            }
            self.setupNextOverlay()
        }
    }

    // MARK: - Asset Discovery

    private func findAssetsDirectory() -> URL {
        // Check bundle first (works in sandboxed screensaver preview)
        if let bundlePath = Bundle(for: AustinSaverView.self).resourceURL {
            let bundleFx = bundlePath.appendingPathComponent(effectsFolder)
            let fxFiles = (try? FileManager.default.contentsOfDirectory(atPath: bundleFx.path)) ?? []
            NSLog("AustinSaver: Bundle path = \(bundlePath.path), effects = \(fxFiles.count)")
            if !fxFiles.isEmpty {
                return bundlePath
            }
        }

        // Hardcoded fallback
        let hardcoded = URL(fileURLWithPath: "/Users/austin/Library/Application Support/AustinScreenSaver")
        let fxFiles = (try? FileManager.default.contentsOfDirectory(atPath: hardcoded.appendingPathComponent(effectsFolder).path)) ?? []
        NSLog("AustinSaver: Hardcoded path effects = \(fxFiles.count)")
        if !fxFiles.isEmpty {
            return hardcoded
        }

        let home = NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/AustinScreenSaver")
    }

    private func findVideos(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }
    }

    // MARK: - Drawing

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }
}
