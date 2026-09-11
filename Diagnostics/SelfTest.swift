import AppKit
import Metal

@MainActor
enum SelfTest {
    static func run() throws {
        let config = AnimationConfig()
        try config.validate()
        guard config.progress(angle: 120) == 0, config.progress(angle: 0) == 1 else {
            throw AppError("Angle endpoint mapping failed")
        }
        var previous: Float = -1
        for a in stride(from: 120.0, through: 0, by: -0.5) {
            let p = config.progress(angle: a)
            guard p >= previous else { throw AppError("Non-monotonic easing") }
            previous = p
        }
        let renderer = try MetalRenderer(config: config)
        print("PASS: Metal source compiled and render pipeline linked on \(renderer.device.name)")
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 128, height: 128, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let input = renderer.device.makeTexture(descriptor: desc),
              let output = renderer.device.makeTexture(descriptor: desc),
              let queue = renderer.device.makeCommandQueue() else { throw AppError("Test texture allocation failed") }
        let white = [UInt8](repeating: 255, count: 128*128*4)
        white.withUnsafeBytes { input.replace(region: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 128*4) }
        for progress: Float in [0, 0.65, 1] {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            let command = queue.makeCommandBuffer()!
            let blurred = try renderer.progressiveBlur.encode(command: command, source: input, strength: config.blurStrength)
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            var uniforms = ShaderUniforms(progress: progress, perspective: config.perspectiveStrength,
                                          blur: config.blurStrength, darkness: config.darkness,
                                          compression: config.verticalCompression, width: 128, height: 128)
            encoder.setRenderPipelineState(renderer.pipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
            encoder.setFragmentTexture(input, index: 0)
            for (index, texture) in blurred.enumerated() { encoder.setFragmentTexture(texture, index: index+1) }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 32*48*6)
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            if let error = command.error { throw error }
            var bytes = [UInt8](repeating: 0, count: 128*128*4)
            bytes.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: 128*4, from: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0) }
            let lit = stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 0 }.count
            if progress == 0 {
                guard lit == 128*128, bytes[0] == 255 else { throw AppError("Open geometry is not pixel-preserving") }
            } else {
                guard lit > 0, lit < 128*128, bytes[0] == 0 else { throw AppError("Fold did not compress into a perspective sheet") }
            }
            print("PASS: GPU offscreen progress=\(progress), lit pixels=\(lit), GPU time=\((command.gpuEndTime-command.gpuStartTime)*1000)ms")
        }
        try renderReference(renderer, config: config)
        print("PASS: easing endpoints / monotonicity")
        print("Screen recording permission: \(CGPreflightScreenCaptureAccess())")
        let sensor = try LidAngleDevice()
        print(String(format: "PASS: Real lid angle: %.1f°", try sensor.read()))
    }
}
