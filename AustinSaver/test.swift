import AppKit
import ScreenSaver

class TestDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
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
