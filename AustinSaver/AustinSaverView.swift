import ScreenSaver
import AVFoundation
import AVKit
import QuartzCore
import CoreImage
import CoreText

// MARK: - Binary Format Structs

struct TTECharacter {
    let column: Int
    let row: Int
    let symbol: String
    let r: UInt8
    let g: UInt8
    let b: UInt8
}

struct TTEFrame {
    let characters: [TTECharacter]
}

struct TTEEffect {
    let name: String
    let gridWidth: Int
    let gridHeight: Int
    let frames: [TTEFrame]
}

// MARK: - Binary Loader

class TTEBinaryLoader {
    static func load(from url: URL) -> TTEEffect? {
        guard let data = try? Data(contentsOf: url) else {
            NSLog("AustinSaver: Failed to read file: \(url.lastPathComponent)")
            return nil
        }

        guard data.count >= 12 else {
            NSLog("AustinSaver: File too small: \(url.lastPathComponent)")
            return nil
        }

        // Check magic
        let magic = String(data: data[0..<4], encoding: .ascii)
        guard magic == "TTE1" else {
            NSLog("AustinSaver: Bad magic in \(url.lastPathComponent)")
            return nil
        }

        let gridWidth = Int(data[4]) | (Int(data[5]) << 8)
        let gridHeight = Int(data[6]) | (Int(data[7]) << 8)
        let frameCount = Int(data[8]) | (Int(data[9]) << 8) | (Int(data[10]) << 16) | (Int(data[11]) << 24)

        var offset = 12
        var frames: [TTEFrame] = []

        for _ in 0..<frameCount {
            guard offset + 2 <= data.count else { break }
            let charCount = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2

            var chars: [TTECharacter] = []
            for _ in 0..<charCount {
                guard offset + 3 <= data.count else { break }
                let col = Int(data[offset])
                let row = Int(data[offset + 1])
                let symLen = Int(data[offset + 2])
                offset += 3

                guard offset + symLen + 3 <= data.count else { break }
                let symData = data[offset..<(offset + symLen)]
                let sym = String(data: symData, encoding: .utf8) ?? "?"
                offset += symLen

                let r = data[offset]
                let g = data[offset + 1]
                let b = data[offset + 2]
                offset += 3

                chars.append(TTECharacter(column: col, row: row, symbol: sym, r: r, g: g, b: b))
            }
            frames.append(TTEFrame(characters: chars))
        }

        let name = url.deletingPathExtension().lastPathComponent
        NSLog("AustinSaver: Loaded \(name): \(gridWidth)x\(gridHeight), \(frames.count) frames")
        return TTEEffect(name: name, gridWidth: gridWidth, gridHeight: gridHeight, frames: frames)
    }
}

// MARK: - Core Text Frame Renderer

class TTEFrameRenderer {
    private var cachedFont: CTFont?
    private var cachedFontSize: CGFloat = 0
    private var cachedViewSize: CGSize = .zero
    private var cachedCellWidth: CGFloat = 0
    private var cachedCellHeight: CGFloat = 0
    private var cachedXOffset: CGFloat = 0
    private var cachedYOffset: CGFloat = 0
    private var gridWidth: Int = 1
    private var gridHeight: Int = 1

    func configure(gridWidth: Int, gridHeight: Int) {
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        cachedViewSize = .zero // Force recalculation
    }

    // Cache for CTLines keyed by symbol + color
    private var lineCache: [UInt64: CTLine] = [:]

    private func cacheKey(symbol: String, r: UInt8, g: UInt8, b: UInt8) -> UInt64 {
        let symHash = UInt64(symbol.hashValue & 0xFFFFFFFF)
        return (symHash << 24) | (UInt64(r) << 16) | (UInt64(g) << 8) | UInt64(b)
    }

    func renderFrame(_ frame: TTEFrame, viewSize: CGSize, scale: CGFloat) -> CGImage? {
        if viewSize != cachedViewSize {
            recalculateLayout(viewSize: viewSize)
            lineCache.removeAll()
        }

        let pixelWidth = Int(viewSize.width * scale)
        let pixelHeight = Int(viewSize.height * scale)

        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        ctx.clear(CGRect(x: 0, y: 0, width: viewSize.width, height: viewSize.height))

        guard let font = cachedFont else { return ctx.makeImage() }
        let descender = CTFontGetDescent(font)

        for char in frame.characters {
            let x = cachedXOffset + CGFloat(char.column - 1) * cachedCellWidth
            let y = viewSize.height - cachedYOffset - CGFloat(char.row) * cachedCellHeight - descender

            ctx.setFillColor(red: CGFloat(char.r) / 255.0,
                           green: CGFloat(char.g) / 255.0,
                           blue: CGFloat(char.b) / 255.0,
                           alpha: 1.0)

            // Block characters: draw as filled rectangles (fast path)
            switch char.symbol {
            case "█":
                ctx.fill(CGRect(x: x, y: y, width: cachedCellWidth, height: cachedCellHeight))
            case "▄":
                ctx.fill(CGRect(x: x, y: y, width: cachedCellWidth, height: cachedCellHeight / 2))
            case "▀":
                ctx.fill(CGRect(x: x, y: y + cachedCellHeight / 2, width: cachedCellWidth, height: cachedCellHeight / 2))
            case "▌":
                ctx.fill(CGRect(x: x, y: y, width: cachedCellWidth / 2, height: cachedCellHeight))
            case "▐":
                ctx.fill(CGRect(x: x + cachedCellWidth / 2, y: y, width: cachedCellWidth / 2, height: cachedCellHeight))
            default:
                // Non-block chars: use cached CTLine
                let key = cacheKey(symbol: char.symbol, r: char.r, g: char.g, b: char.b)
                let line: CTLine
                if let cached = lineCache[key] {
                    line = cached
                } else {
                    let color = NSColor(red: CGFloat(char.r) / 255.0,
                                       green: CGFloat(char.g) / 255.0,
                                       blue: CGFloat(char.b) / 255.0,
                                       alpha: 1.0)
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font as Any,
                        .foregroundColor: color
                    ]
                    let attrStr = NSAttributedString(string: char.symbol, attributes: attributes)
                    line = CTLineCreateWithAttributedString(attrStr)
                    lineCache[key] = line
                }
                ctx.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(line, ctx)
            }
        }

        return ctx.makeImage()
    }

    private func recalculateLayout(viewSize: CGSize) {
        cachedViewSize = viewSize
        // Fill the full view — grid maps 1:1 to screen
        cachedCellWidth = viewSize.width / CGFloat(gridWidth)
        cachedCellHeight = viewSize.height / CGFloat(gridHeight)
        // fontSize = cellHeight so block chars (█ ▄ ▀) fill the entire cell
        cachedFontSize = cachedCellHeight
        cachedFont = CTFontCreateWithName("Menlo-Bold" as CFString, cachedFontSize, nil)
        cachedXOffset = 0
        cachedYOffset = 0
    }
}

// MARK: - Main Screensaver View

class AustinSaverView: ScreenSaverView {

    // Background video
    private var backgroundPlayer: AVQueuePlayer?
    private var backgroundLayer: AVPlayerLayer?
    private var backgroundLooper: AVPlayerLooper?

    // TTE overlay
    private var overlayLayer: CALayer?
    private var renderer = TTEFrameRenderer()
    private var effects: [TTEEffect] = []
    private var currentEffectIndex = 0
    private var currentFrameIndex = 0
    private var pauseCounter = 0
    private let pauseFrames = 60 // ~2 seconds at 30fps

    private let backgroundsFolder = "AustinBackgrounds"
    private let effectsFolder = "AustinEffects"

    // MARK: - Lifecycle

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60.0
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
        NotificationCenter.default.removeObserver(self)
        backgroundPlayer?.pause()
        backgroundPlayer = nil
        backgroundLayer?.removeFromSuperlayer()
        backgroundLayer = nil
        backgroundLooper = nil
        overlayLayer?.removeFromSuperlayer()
        overlayLayer = nil
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

        // Load background videos — use Apple's built-in aerials, fall back to bundled
        let appleAerialDirs = [
            "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS",
            "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR",
            "/Library/Application Support/com.apple.idleassetsd/Customer/4KHDR",
        ]
        var bgVideos: [URL] = []
        for dir in appleAerialDirs {
            let url = URL(fileURLWithPath: dir)
            let found = findFiles(in: url, extensions: ["mov", "mp4", "m4v"])
            bgVideos.append(contentsOf: found)
        }
        // Fall back to bundled backgrounds if no Apple aerials found
        if bgVideos.isEmpty {
            bgVideos = findFiles(in: assetsBase.appendingPathComponent(backgroundsFolder), extensions: ["mp4", "mov", "m4v"])
        }
        NSLog("AustinSaver: Found \(bgVideos.count) background videos")

        // Load TTE effect data
        let tteFiles = findFiles(in: assetsBase.appendingPathComponent(effectsFolder), extensions: ["tte"])
        // Sort by modification date (newest first) so the latest effect plays first
        let sortedFiles = tteFiles.sorted { a, b in
            let aDate = (try? FileManager.default.attributesOfItem(atPath: a.path)[.modificationDate] as? Date) ?? Date.distantPast
            let bDate = (try? FileManager.default.attributesOfItem(atPath: b.path)[.modificationDate] as? Date) ?? Date.distantPast
            return aDate > bDate
        }
        // Load ONLY the first effect immediately, load rest in background
        if let first = sortedFiles.first, let firstEffect = TTEBinaryLoader.load(from: first) {
            effects = [firstEffect]
            NSLog("AustinSaver: Loaded first effect, loading \(sortedFiles.count - 1) more in background")

            let remaining = Array(sortedFiles.dropFirst())
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let rest = remaining.compactMap { TTEBinaryLoader.load(from: $0) }.shuffled()
                DispatchQueue.main.async {
                    self?.effects.append(contentsOf: rest)
                    NSLog("AustinSaver: Background loading complete. Total: \(self?.effects.count ?? 0) effects")
                }
            }
        }
        NSLog("AustinSaver: \(bgVideos.count) backgrounds")

        // Setup background video
        if let bgVideo = bgVideos.randomElement() {
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

        // Setup overlay layer for Core Text rendering
        let ovLayer = CALayer()
        ovLayer.frame = layer.bounds
        ovLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        ovLayer.contentsGravity = .resizeAspect
        if let filter = CIFilter(name: "CIScreenBlendMode") {
            ovLayer.compositingFilter = filter
        }
        layer.addSublayer(ovLayer)
        self.overlayLayer = ovLayer

        // Configure renderer for first effect
        if let effect = effects.first {
            renderer.configure(gridWidth: effect.gridWidth, gridHeight: effect.gridHeight)
        }

        currentEffectIndex = 0
        currentFrameIndex = 0
        pauseCounter = 0
    }

    // MARK: - Animation

    private var frameTimeAccum: Double = 0
    private var frameCount: Int = 0
    private var lastLogTime: Double = 0

    override func animateOneFrame() {
        guard !effects.isEmpty, let ovLayer = overlayLayer else { return }

        let effect = effects[currentEffectIndex % effects.count]

        // Pausing on final frame
        if pauseCounter > 0 {
            pauseCounter -= 1
            if pauseCounter == 0 {
                advanceEffect()
            }
            return
        }

        // Render current frame
        if currentFrameIndex < effect.frames.count {
            let start = CACurrentMediaTime()
            let frame = effect.frames[currentFrameIndex]
            let scale = self.window?.backingScaleFactor ?? 2.0
            if let image = renderer.renderFrame(frame, viewSize: ovLayer.bounds.size, scale: scale) {
                ovLayer.contents = image
                ovLayer.contentsScale = scale
            }
            let elapsed = CACurrentMediaTime() - start
            frameTimeAccum += elapsed
            frameCount += 1
            let now = CACurrentMediaTime()
            if frameCount % 60 == 0 {
                let avgMs = (frameTimeAccum / Double(frameCount)) * 1000.0
                let actualFps = lastLogTime > 0 ? 60.0 / (now - lastLogTime) : 0
                NSLog("AustinSaver: render=%.1fms, actual fps=%.0f, chars=\(frame.characters.count)", avgMs, actualFps)
                lastLogTime = now
            }
            // 1.5x speed: alternate between advancing 1 and 2 frames
            currentFrameIndex += (currentFrameIndex % 2 == 0) ? 2 : 1
        } else {
            // Effect finished — pause on final frame then advance
            pauseCounter = pauseFrames
        }
    }

    private func advanceEffect() {
        currentEffectIndex += 1
        currentFrameIndex = 0

        // Reshuffle when we've gone through all
        if currentEffectIndex >= effects.count {
            currentEffectIndex = 0
            effects.shuffle()
            NSLog("AustinSaver: Reshuffled effects")
        }

        let effect = effects[currentEffectIndex]
        renderer.configure(gridWidth: effect.gridWidth, gridHeight: effect.gridHeight)
        NSLog("AustinSaver: Now playing: \(effect.name) (\(effect.frames.count) frames)")
    }

    // MARK: - Asset Discovery

    private func findAssetsDirectory() -> URL {
        if let bundlePath = Bundle(for: AustinSaverView.self).resourceURL {
            let bundleFx = bundlePath.appendingPathComponent(effectsFolder)
            let fxFiles = (try? FileManager.default.contentsOfDirectory(atPath: bundleFx.path)) ?? []
            NSLog("AustinSaver: Bundle path = \(bundlePath.path), effects = \(fxFiles.count)")
            if !fxFiles.isEmpty {
                return bundlePath
            }
        }

        let home = NSHomeDirectory()
        let hardcoded = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/AustinScreenSaver")
        let fxFiles = (try? FileManager.default.contentsOfDirectory(atPath: hardcoded.appendingPathComponent(effectsFolder).path)) ?? []
        NSLog("AustinSaver: Hardcoded path effects = \(fxFiles.count)")
        if !fxFiles.isEmpty {
            return hardcoded
        }

        return hardcoded
    }

    private func findFiles(in directory: URL, extensions: [String]) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { extensions.contains($0.pathExtension.lowercased()) }
    }

    // MARK: - Drawing

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }
}
