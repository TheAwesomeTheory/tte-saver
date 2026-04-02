import AppKit
import ScreenSaver
import AVFoundation

class TestDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("TEST: Starting up")

        // Test asset discovery manually
        let home = NSHomeDirectory()
        NSLog("TEST: Home = \(home)")

        let assetsDir = "/Users/austin/Library/Application Support/AustinScreenSaver"
        let bgDir = "\(assetsDir)/AustinBackgrounds"
        let fxDir = "\(assetsDir)/AustinEffects"

        NSLog("TEST: Assets exists = \(FileManager.default.fileExists(atPath: assetsDir))")
        NSLog("TEST: BG dir exists = \(FileManager.default.fileExists(atPath: bgDir))")
        NSLog("TEST: FX dir exists = \(FileManager.default.fileExists(atPath: fxDir))")

        let bgFiles = (try? FileManager.default.contentsOfDirectory(atPath: bgDir)) ?? []
        let fxFiles = (try? FileManager.default.contentsOfDirectory(atPath: fxDir)) ?? []
        NSLog("TEST: BG files = \(bgFiles.count), FX files = \(fxFiles.count)")

        // Test playing a video directly
        if let firstBg = bgFiles.first {
            let url = URL(fileURLWithPath: "\(bgDir)/\(firstBg)")
            NSLog("TEST: Trying to play \(url.path)")
            let asset = AVAsset(url: url)
            NSLog("TEST: Asset playable = \(asset.isPlayable)")
        }

        // Now test the actual view
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AustinSaver Test"
        window.center()

        if let view = AustinSaverView(frame: frame, isPreview: false) {
            window.contentView = view
            view.startAnimation()
            NSLog("TEST: View created OK")
        } else {
            NSLog("TEST: View creation FAILED")
        }

        window.makeKeyAndOrderFront(nil)
    }
}

@main
struct TestApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = TestDelegate()
        app.delegate = delegate
        app.run()
    }
}
