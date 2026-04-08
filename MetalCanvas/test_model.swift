import AppKit
import SceneKit
import ModelIO
import SceneKit.ModelIO

class ModelTestDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "3D Model Viewer"
        window.center()

        let sceneView = SCNView(frame: NSRect(origin: .zero, size: frame.size))
        sceneView.autoresizingMask = [.width, .height]
        sceneView.allowsCameraControl = true
        sceneView.backgroundColor = .black
        sceneView.autoenablesDefaultLighting = true

        // Load via ModelIO (better glTF support than SceneKit directly)
        let url = URL(fileURLWithPath: "\(FileManager.default.currentDirectoryPath)/MetalCanvas/model.obj")
        NSLog("Loading from: \(url.path)")

        let mdlAsset = MDLAsset(url: url)
        mdlAsset.loadTextures()

        NSLog("ModelIO loaded: \(mdlAsset.count) top-level objects")

        let scene = SCNScene(mdlAsset: mdlAsset)
        NSLog("Scene nodes: \(scene.rootNode.childNodes.count)")

        // Log structure
        func printNode(_ node: SCNNode, indent: String = "") {
            let geo = node.geometry != nil ? " [geo: \(node.geometry!.elements.count) elements, \(node.geometry!.sources.count) sources]" : ""
            NSLog("\(indent)'\(node.name ?? "?")' pos:\(node.position) scale:\(node.scale)\(geo)")
            for child in node.childNodes {
                printNode(child, indent: indent + "  ")
            }
        }
        printNode(scene.rootNode)

        // Get bounding box
        let (minB, maxB) = scene.rootNode.boundingBox
        let size = max(maxB.x - minB.x, max(maxB.y - minB.y, maxB.z - minB.z))
        let center = SCNVector3((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, (minB.z + maxB.z) / 2)
        NSLog("Bounds: min=\(minB) max=\(maxB) size=\(size) center=\(center)")

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera!.automaticallyAdjustsZRange = true
        cameraNode.position = SCNVector3(center.x, center.y, center.z + size * 2.5)
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)

        // Lights
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.intensity = 800
        ambientLight.light!.color = NSColor.white
        scene.rootNode.addChildNode(ambientLight)

        let dirLight = SCNNode()
        dirLight.light = SCNLight()
        dirLight.light!.type = .directional
        dirLight.light!.intensity = 1200
        dirLight.light!.color = NSColor.white
        dirLight.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(dirLight)

        // Auto-rotate all model nodes
        for child in scene.rootNode.childNodes {
            if child.camera == nil && child.light == nil {
                let rotation = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 8))
                child.runAction(rotation)
            }
        }

        sceneView.scene = scene
        sceneView.pointOfView = cameraNode

        window.contentView = sceneView
        window.makeKeyAndOrderFront(nil)
    }
}

@main
struct ModelTestApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = ModelTestDelegate()
        app.delegate = delegate
        app.run()
    }
}
