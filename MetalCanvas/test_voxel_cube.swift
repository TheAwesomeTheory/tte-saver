import AppKit
import SceneKit

class VoxelCubeDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Voxel Rubik's Cube"
        window.center()

        let sceneView = SCNView(frame: NSRect(origin: .zero, size: frame.size))
        sceneView.autoresizingMask = [.width, .height]
        sceneView.allowsCameraControl = true
        sceneView.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
        sceneView.autoenablesDefaultLighting = true
        sceneView.antialiasingMode = .multisampling4X

        let scene = SCNScene()

        guard let (centers, colors, pitch) = loadVoxelData() else {
            NSLog("Failed to load voxel data")
            return
        }
        NSLog("Loaded \(centers.count) voxels, pitch=\(pitch)")

        // Find centroid
        var cx: Float = 0, cy: Float = 0, cz: Float = 0
        for c in centers { cx += c.0; cy += c.1; cz += c.2 }
        cx /= Float(centers.count); cy /= Float(centers.count); cz /= Float(centers.count)

        // Build one merged geometry per piece (8 pieces)
        let gap: Float = 0.06
        let rootNode = SCNNode()

        for xi in 0..<2 {
            for yi in 0..<2 {
                for zi in 0..<2 {
                    // Collect voxels for this piece
                    var pieceVerts: [SCNVector3] = []
                    var pieceNorms: [SCNVector3] = []
                    var pieceColors: [NSColor] = []
                    var pieceIndices: [UInt32] = []

                    for i in 0..<centers.count {
                        let (x, y, z) = centers[i]
                        let isLeft = x < cx
                        let isBottom = y < cy
                        let isBack = z < cz

                        if (isLeft == (xi == 0)) && (isBottom == (yi == 0)) && (isBack == (zi == 0)) {
                            let (r, g, b) = colors[i]
                            let color = NSColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1)
                            let lx = x - cx
                            let ly = y - cy
                            let lz = z - cz
                            let hp = pitch * 0.48  // Slightly smaller than half-pitch for tiny gaps

                            // Add a cube (8 vertices, 12 triangles)
                            let baseIdx = UInt32(pieceVerts.count)

                            // 8 corners of the cube
                            let corners: [(Float, Float, Float)] = [
                                (lx - hp, ly - hp, lz - hp), (lx + hp, ly - hp, lz - hp),
                                (lx + hp, ly + hp, lz - hp), (lx - hp, ly + hp, lz - hp),
                                (lx - hp, ly - hp, lz + hp), (lx + hp, ly - hp, lz + hp),
                                (lx + hp, ly + hp, lz + hp), (lx - hp, ly + hp, lz + hp),
                            ]
                            for c in corners {
                                pieceVerts.append(SCNVector3(c.0, c.1, c.2))
                                pieceNorms.append(SCNVector3(0, 1, 0))
                                pieceColors.append(color)
                            }

                            // 6 faces, 2 triangles each
                            let faces: [(UInt32, UInt32, UInt32)] = [
                                (0,1,2),(0,2,3), // front
                                (4,6,5),(4,7,6), // back
                                (0,4,5),(0,5,1), // bottom
                                (2,6,7),(2,7,3), // top
                                (0,3,7),(0,7,4), // left
                                (1,5,6),(1,6,2), // right
                            ]
                            for (a, b, c) in faces {
                                pieceIndices.append(baseIdx + a)
                                pieceIndices.append(baseIdx + b)
                                pieceIndices.append(baseIdx + c)
                            }
                        }
                    }

                    if pieceVerts.isEmpty { continue }

                    // Create merged geometry
                    let vertexSource = SCNGeometrySource(vertices: pieceVerts)
                    let normalSource = SCNGeometrySource(normals: pieceNorms)

                    // Color source — use floats for compatibility
                    var colorFloats: [Float] = []
                    for c in pieceColors {
                        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                        c.getRed(&r, green: &g, blue: &b, alpha: &a)
                        colorFloats.append(Float(r))
                        colorFloats.append(Float(g))
                        colorFloats.append(Float(b))
                    }
                    let colorData = Data(bytes: colorFloats, count: colorFloats.count * MemoryLayout<Float>.size)
                    let colorSource = SCNGeometrySource(data: colorData,
                        semantic: .color,
                        vectorCount: pieceColors.count,
                        usesFloatComponents: true,
                        componentsPerVector: 3,
                        bytesPerComponent: MemoryLayout<Float>.size,
                        dataOffset: 0,
                        dataStride: MemoryLayout<Float>.size * 3)

                    let indexData = Data(bytes: pieceIndices, count: pieceIndices.count * 4)
                    let element = SCNGeometryElement(data: indexData,
                        primitiveType: .triangles,
                        primitiveCount: pieceIndices.count / 3,
                        bytesPerIndex: 4)

                    let geometry = SCNGeometry(sources: [vertexSource, normalSource, colorSource], elements: [element])
                    // Constant lighting — vertex colors show as-is, no dark angles
                    geometry.firstMaterial?.lightingModel = .constant

                    let pieceNode = SCNNode(geometry: geometry)
                    let offsetX = Float(xi) * gap * 2 - gap
                    let offsetY = Float(yi) * gap * 2 - gap
                    let offsetZ = Float(zi) * gap * 2 - gap
                    pieceNode.position = SCNVector3(offsetX, offsetY, offsetZ)

                    rootNode.addChildNode(pieceNode)
                    NSLog("Piece [\(xi),\(yi),\(zi)]: \(pieceVerts.count / 8) voxels, \(pieceVerts.count) verts")
                }
            }
        }

        scene.rootNode.addChildNode(rootNode)

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera!.automaticallyAdjustsZRange = true
        cameraNode.position = SCNVector3(0, 0.2, 2.5)
        cameraNode.look(at: SCNVector3(0, 0.1, 0))
        scene.rootNode.addChildNode(cameraNode)

        sceneView.scene = scene
        sceneView.pointOfView = cameraNode
        window.contentView = sceneView
        window.makeKeyAndOrderFront(nil)
    }

    func loadVoxelData() -> ([(Float, Float, Float)], [(UInt8, UInt8, UInt8)], Float)? {
        guard let content = try? String(contentsOfFile: "MetalCanvas/voxels.csv", encoding: .utf8) else { return nil }
        var centers: [(Float, Float, Float)] = []
        var colors: [(UInt8, UInt8, UInt8)] = []
        var pitch: Float = 0.03
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: ",")
            if parts.count == 1 {
                pitch = Float(parts[0]) ?? 0.03
            } else if parts.count >= 6 {
                centers.append((Float(parts[0])!, Float(parts[1])!, Float(parts[2])!))
                colors.append((UInt8(parts[3])!, UInt8(parts[4])!, UInt8(parts[5])!))
            }
        }
        return (centers, colors, pitch)
    }
}

@main
struct VoxelCubeApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = VoxelCubeDelegate()
        app.delegate = delegate
        app.run()
    }
}
