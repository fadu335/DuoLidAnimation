import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreVideo

/// Pixel buffers are retained, never locked or copied into CPU memory.
final class CapturedFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
    let timestamp: CFTimeInterval
    init(_ buffer: CVPixelBuffer) { self.buffer = buffer; timestamp = CACurrentMediaTime() }
}

@MainActor
final class ScreenCaptureManager: NSObject, SCStreamOutput, SCStreamDelegate {
    nonisolated let latest = Mailbox<CapturedFrame?>(nil)
    nonisolated let failure = Mailbox<String?>(nil)
    private let outputQueue = DispatchQueue(label: "duolid.capture", qos: .userInteractive)
    private var stream: SCStream?
    private let captureBackground = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

    func start(displayID: CGDirectDisplayID, pixelWidth: Int, pixelHeight: Int) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw AppError("Встроенный экран недоступен для захвата")
        }
        let ownApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        guard !ownApplications.isEmpty else {
            throw AppError("ScreenCaptureKit не нашёл процесс приложения. Захват остановлен, чтобы исключить рекурсию.")
        }
        // Application-level exclusion also covers windows created after this filter.
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3
        config.showsCursor = false // The live hardware cursor remains usable above the overlay.
        config.capturesAudio = false
        config.scalesToFit = true
        config.captureResolution = .best
        config.colorSpaceName = CGColorSpace.sRGB
        config.backgroundColor = captureBackground
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        stream = newStream
        try await newStream.startCapture()
        NSLog("Capture started: %dx%d; own process explicitly excluded", pixelWidth, pixelHeight)
    }
    func stop() async {
        if let stream { try? await stream.stopCapture() }
        stream = nil
        latest.set(nil)
    }
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int else { return }
        if raw == SCFrameStatus.idle.rawValue { return } // Keep a valid static desktop texture.
        guard raw == SCFrameStatus.complete.rawValue else { latest.set(nil); return }
        guard let buffer = sampleBuffer.imageBuffer else { return }
        latest.set(CapturedFrame(buffer))
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        latest.set(nil)
        failure.set(error.localizedDescription)
        NSLog("ScreenCaptureKit stopped: %@", error.localizedDescription)
    }
}
