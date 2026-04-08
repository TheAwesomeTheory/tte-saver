import AppKit
import ScreenSaver

class TestDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main!
        let frame = screen.frame
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver

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
