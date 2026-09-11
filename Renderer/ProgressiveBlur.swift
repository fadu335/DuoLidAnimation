import Metal
import MetalPerformanceShaders

/// Three Gaussian scales on a quarter-resolution surface. The fragment shader
/// blends them in different vertical bands, leaving the bottom hinge crisp.
@MainActor
final class ProgressiveBlur {
    private let device: MTLDevice
    private let downsample: MPSImageLanczosScale
    private var kernels: [MPSImageGaussianBlur] = []
    private var reduced: MTLTexture?
    private var outputs: [MTLTexture] = []
    private var strength: Float = -1
    private var sourceWidth = 0
    private var sourceHeight = 0

    init(device: MTLDevice) {
        self.device = device
        downsample = MPSImageLanczosScale(device: device)
        downsample.edgeMode = .clamp
    }

    func encode(command: MTLCommandBuffer, source: MTLTexture, strength: Float) throws -> [MTLTexture] {
        let w = max(1, source.width / 4), h = max(1, source.height / 4)
        if reduced?.width != w || reduced?.height != h || self.strength != strength
            || sourceWidth != source.width || sourceHeight != source.height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            guard let small = device.makeTexture(descriptor: descriptor) else { throw AppError("Blur texture allocation failed") }
            reduced = small
            outputs = try (0..<3).map { _ in
                guard let texture = device.makeTexture(descriptor: descriptor) else { throw AppError("Gaussian texture allocation failed") }
                return texture
            }
            // Radius is specified relative to an 880px-wide reference, independent of Retina scaling.
            let scale = Float(w) / 880
            kernels = [Float(6.0/36), Float(16.0/36), 1].map {
                let kernel = MPSImageGaussianBlur(device: device, sigma: max(0.1, strength * $0 * scale))
                kernel.edgeMode = .clamp
                return kernel
            }
            self.strength = strength
            sourceWidth = source.width; sourceHeight = source.height
        }
        guard let reduced else { throw AppError("Blur surface missing") }
        downsample.encode(commandBuffer: command, sourceTexture: source, destinationTexture: reduced)
        for index in 0..<3 {
            kernels[index].encode(commandBuffer: command, sourceTexture: reduced, destinationTexture: outputs[index])
        }
        return outputs
    }
}
