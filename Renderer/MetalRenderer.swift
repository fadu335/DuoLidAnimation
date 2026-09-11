import MetalKit
import CoreVideo

struct ShaderUniforms {
    var progress: Float
    var perspective: Float
    var blur: Float
    var darkness: Float
    var compression: Float
    var width: Float
    var height: Float
    var padding: Float = 0
}

@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let pipeline: MTLRenderPipelineState
    private let commandQueue: MTLCommandQueue
    private var cache: CVMetalTextureCache!
    let progressiveBlur: ProgressiveBlur
    private var blurredFrame: CapturedFrame?
    private var blurredTextures: [MTLTexture] = []
    private let inFlight = DispatchSemaphore(value: 2)
    private let gpuError = Mailbox<String?>(nil)
    var frame: CapturedFrame?
    var progress: Float = 0
    var config: AnimationConfig
    private(set) var submittedFrames: UInt64 = 0

    init(config: AnimationConfig) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw AppError("Metal GPU недоступен")
        }
        self.device = device
        progressiveBlur = ProgressiveBlur(device: device)
        commandQueue = queue
        self.config = config
        guard let url = Bundle.main.url(forResource: "Shaders", withExtension: "metal") else {
            throw AppError("Shaders.metal отсутствует в Resources")
        }
        let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess else {
            throw AppError("Не удалось создать CVMetalTextureCache")
        }
    }
    var error: String? { gpuError.get() }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let frame, inFlight.wait(timeout: .now()) == .success else { return }
        var committed = false
        defer { if !committed { inFlight.signal() } }
        let buffer = frame.buffer
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        var wrapper: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, nil,
                                                               .bgra8Unorm, width, height, 0, &wrapper)
        guard result == kCVReturnSuccess, let wrapper, let texture = CVMetalTextureGetTexture(wrapper),
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = commandQueue.makeCommandBuffer() else { return }
        if blurredFrame !== frame || blurredTextures.isEmpty {
            do {
                blurredTextures = try progressiveBlur.encode(command: command, source: texture, strength: config.blurStrength)
            } catch { gpuError.set(error.localizedDescription); return }
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = ShaderUniforms(progress: progress, perspective: config.perspectiveStrength,
                                      blur: config.blurStrength, darkness: config.darkness,
                                      compression: config.verticalCompression, width: Float(width), height: Float(height))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        for (index, blurred) in blurredTextures.enumerated() { encoder.setFragmentTexture(blurred, index: index + 1) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 32 * 48 * 6)
        encoder.endEncoding()
        // Retain the IOSurface/CVMetalTexture until the GPU completes, including if capture replaces its mailbox.
        let retained = GPUFrameLifetime(frame: frame, wrapper: wrapper)
        let semaphore = inFlight, errors = gpuError
        command.addCompletedHandler { @Sendable completed in
            withExtendedLifetime(retained) {}
            if let error = completed.error { errors.set(error.localizedDescription) }
            semaphore.signal()
        }
        command.present(drawable)
        command.commit()
        blurredFrame = frame
        committed = true
        submittedFrames += 1
    }
}
private final class GPUFrameLifetime: @unchecked Sendable {
    let frame: CapturedFrame
    let wrapper: CVMetalTexture
    init(frame: CapturedFrame, wrapper: CVMetalTexture) { self.frame = frame; self.wrapper = wrapper }
}
