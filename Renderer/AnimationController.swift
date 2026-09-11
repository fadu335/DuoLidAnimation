import Foundation

struct AnimationConfig: Codable, Sendable {
    var startAngle: Double = 100
    var endAngle: Double = 8
    var perspectiveStrength: Float = 0.38
    var blurStrength: Float = 36
    var darkness: Float = 0.9
    var verticalCompression: Float = 1.0
    var easing = "smoothstep"
    var animationSensitivity: Double = 1

    static var userURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DuoLidAnimation/AnimationConfig.json")
    }
    static func load() throws -> AnimationConfig {
        let url = userURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let bundled = Bundle.main.url(forResource: "AnimationConfig", withExtension: "json") else {
                throw AppError("AnimationConfig.json отсутствует в приложении")
            }
            try FileManager.default.copyItem(at: bundled, to: url)
        }
        let result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try result.validate()
        return result
    }
    func validate() throws {
        guard startAngle.isFinite, endAngle.isFinite, startAngle > endAngle + 1,
              endAngle >= 0, startAngle <= 180,
              perspectiveStrength.isFinite, (0...2).contains(perspectiveStrength),
              blurStrength.isFinite, (0...80).contains(blurStrength),
              darkness.isFinite, (0...1).contains(darkness),
              verticalCompression.isFinite, (0...1).contains(verticalCompression),
              animationSensitivity.isFinite, (0.2...3).contains(animationSensitivity),
              ["smoothstep", "cubic", "linear"].contains(easing) else {
            throw AppError("Недопустимые параметры AnimationConfig.json. См. README.")
        }
    }
    func progress(angle: Double) -> Float {
        let t = pow(min(1, max(0, (startAngle - angle) / (startAngle - endAngle))), 1 / animationSensitivity)
        switch easing {
        case "linear": return Float(t)
        case "cubic": return Float(t < 0.5 ? 4*t*t*t : 1 - pow(-2*t+2, 3)/2)
        default: return Float(t*t*(3-2*t))
        }
    }
}

struct AnimationController {
    var config: AnimationConfig
    private(set) var progress: Float = 0
    private var previousTime: Double?
    init(config: AnimationConfig) { self.config = config }
    mutating func synchronize(angle: Double, now: Double) {
        progress = config.progress(angle: angle)
        previousTime = now
    }
    mutating func update(angle: Double, now: Double) -> Float {
        let dt = min(0.1, max(0.001, now - (previousTime ?? now - 1.0/60)))
        previousTime = now
        // ~22ms time constant removes integer-degree sensor stepping without long trailing motion.
        let alpha = Float(1 - exp(-dt / 0.022))
        progress += (config.progress(angle: angle) - progress) * alpha
        if progress < 0.0001 { progress = 0 }
        return progress
    }
}
