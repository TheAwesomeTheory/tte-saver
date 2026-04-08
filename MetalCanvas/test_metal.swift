import AppKit
import Metal
import MetalKit

class MetalTestDelegate: NSObject, NSApplicationDelegate, MTKViewDelegate {
    var window: NSWindow!
    var canvas: MetalCanvas!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "MetalCanvas Test"
        window.center()

        guard let canvas = MetalCanvas(frame: frame) else {
            NSLog("Failed to create MetalCanvas")
            return
        }
        self.canvas = canvas

        // Load shaders from the .metal file
        let shaderURL = URL(fileURLWithPath: "MetalCanvas/shaders.metal")
        do {
            try canvas.loadShaders(from: shaderURL)
            try canvas.createPipeline(name: "plasma", vertex: "vertexPassthrough", fragment: "plasmaFragment")
            NSLog("Pipelines ready")
        } catch {
            NSLog("Shader error: \(error)")
            return
        }

        // Set up the render callback — just draw plasma
        canvas.onRender { [weak self] encoder, descriptor, size, time in
            self?.canvas.drawQuad(encoder: encoder, pipeline: "plasma")
        }

        // Use MTKView delegate for rendering
        canvas.view.delegate = self
        canvas.view.frame = NSRect(origin: .zero, size: frame.size)

        window.contentView = canvas.view
        window.makeKeyAndOrderFront(nil)
    }

    // MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        canvas?.render()
    }
}

@main
struct MetalTestApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = MetalTestDelegate()
        app.delegate = delegate
        app.run()
    }
}
