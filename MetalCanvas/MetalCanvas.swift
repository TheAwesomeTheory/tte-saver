import AppKit
import Metal
import MetalKit
import QuartzCore

/// A self-contained Metal rendering canvas that can be embedded in any NSView.
/// Loads shaders from .metal files at runtime — no Xcode required.
public class MetalCanvas {

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let view: MTKView

    private var library: MTLLibrary?
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var vertexBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?
    private var startTime: CFTimeInterval = 0
    private var renderCallback: ((MTLRenderCommandEncoder, MTLRenderPassDescriptor, CGSize, Double) -> Void)?

    // MARK: - Quad vertices (fullscreen triangle strip)

    private static let quadVertices: [Float] = [
        // position    // uv
        -1,  1,        0, 0,   // top-left
        -1, -1,        0, 1,   // bottom-left
         1,  1,        1, 0,   // top-right
         1, -1,        1, 1,   // bottom-right
    ]

    // MARK: - Uniforms

    struct Uniforms {
        var time: Float
        var resolutionX: Float
        var resolutionY: Float
    }

    // MARK: - Init

    public init?(frame: NSRect) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("MetalCanvas: No Metal device")
            return nil
        }
        guard let queue = device.makeCommandQueue() else {
            NSLog("MetalCanvas: Failed to create command queue")
            return nil
        }

        self.device = device
        self.commandQueue = queue

        // Create MTKView
        view = MTKView(frame: frame, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.layer?.isOpaque = false
        view.preferredFramesPerSecond = 60
        view.autoresizingMask = [.width, .height]

        // Create vertex buffer
        let dataSize = MetalCanvas.quadVertices.count * MemoryLayout<Float>.size
        vertexBuffer = device.makeBuffer(bytes: MetalCanvas.quadVertices, length: dataSize)

        // Create uniform buffer
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.size, options: .storageModeShared)

        startTime = CACurrentMediaTime()
    }

    // MARK: - Shader Loading

    /// Load shaders from a .metal file. Call this before creating pipelines.
    public func loadShaders(from url: URL) throws {
        let source = try String(contentsOf: url, encoding: .utf8)
        library = try device.makeLibrary(source: source, options: nil)
        NSLog("MetalCanvas: Loaded shaders from \(url.lastPathComponent)")
    }

    /// Load shaders from a source string.
    public func loadShaders(source: String) throws {
        library = try device.makeLibrary(source: source, options: nil)
        NSLog("MetalCanvas: Loaded shaders from string")
    }

    // MARK: - Pipeline Creation

    /// Create a render pipeline with the given vertex and fragment function names.
    public func createPipeline(name: String, vertex: String, fragment: String, blending: Bool = false) throws {
        guard let library = library else {
            throw MetalCanvasError.noLibrary
        }
        guard let vertexFn = library.makeFunction(name: vertex) else {
            throw MetalCanvasError.functionNotFound(vertex)
        }
        guard let fragmentFn = library.makeFunction(name: fragment) else {
            throw MetalCanvasError.functionNotFound(fragment)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat

        if blending {
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        // Vertex descriptor for our quad
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
        descriptor.vertexDescriptor = vertexDescriptor

        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        pipelines[name] = pipeline
        NSLog("MetalCanvas: Created pipeline '\(name)'")
    }

    // MARK: - Texture Creation

    /// Create a Metal texture from a CGImage.
    public func makeTexture(from image: CGImage) -> MTLTexture? {
        let loader = MTKTextureLoader(device: device)
        return try? loader.newTexture(cgImage: image, options: [
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .SRGB: NSNumber(value: false)
        ])
    }

    /// Create an empty texture of the given size.
    public func makeTexture(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        return device.makeTexture(descriptor: descriptor)
    }

    // MARK: - Rendering

    /// Set the render callback. Called each frame with the encoder, pass descriptor, size, and time.
    public func onRender(_ callback: @escaping (MTLRenderCommandEncoder, MTLRenderPassDescriptor, CGSize, Double) -> Void) {
        renderCallback = callback
    }

    /// Draw a fullscreen quad with the given pipeline and textures.
    public func drawQuad(encoder: MTLRenderCommandEncoder, pipeline: String, textures: [MTLTexture] = []) {
        guard let pipelineState = pipelines[pipeline] else {
            NSLog("MetalCanvas: Pipeline '\(pipeline)' not found")
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // Update and bind uniforms
        let time = Float(CACurrentMediaTime() - startTime)
        var uniforms = Uniforms(
            time: time,
            resolutionX: Float(view.drawableSize.width),
            resolutionY: Float(view.drawableSize.height)
        )
        uniformBuffer?.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<Uniforms>.size)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

        for (i, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: i)
        }

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// Render a single frame. Call this from your display link or animation loop.
    public func render() {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        if let callback = renderCallback,
           let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            let size = view.drawableSize
            let time = CACurrentMediaTime() - startTime
            callback(encoder, descriptor, size, time)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Errors

    public enum MetalCanvasError: Error {
        case noLibrary
        case functionNotFound(String)
    }
}
