import Foundation
import IOKit.hid
import QuartzCore

/// Only accessed on its owning serial queue, or synchronously by the diagnostic CLI.
/// No SMC writes, no device seizure, no synthetic fallback angles.
final class LidAngleDevice {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private var reportType = kIOHIDReportTypeFeature

    init() throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [
            "VendorID": 0x05AC, "DeviceUsagePage": 0x20, "DeviceUsage": 0x8A
        ] as CFDictionary)
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        guard let candidate = devices.first else {
            throw AppError("Датчик угла крышки HID 0x20/0x8A не найден. Искусственные значения не используются.")
        }
        device = candidate
        let result = IOHIDDeviceOpen(device, 0)
        guard result == kIOReturnSuccess else {
            throw AppError(String(format: "IOHIDDeviceOpen: 0x%08x. Датчик недоступен.", result))
        }
        // Apple SPU implements Feature GetReport even though its descriptor labels report 1 Input.
        do { _ = try read() } catch {
            reportType = kIOHIDReportTypeInput
            _ = try read()
        }
    }

    func read() throws -> Double {
        var bytes = [UInt8](repeating: 0, count: 16)
        var length = bytes.count
        let result = IOHIDDeviceGetReport(device, reportType, 1, &bytes, &length)
        guard result == kIOReturnSuccess else {
            throw AppError(String(format: "IOHIDDeviceGetReport: 0x%08x", result))
        }
        guard length >= 3, bytes[0] == 1 else { throw AppError("Неизвестный формат HID report 1: \(bytes.prefix(length))") }
        let angle = Int(bytes[1]) | (Int(bytes[2]) << 8)
        guard (0...360).contains(angle) else { throw AppError("Недопустимый угол датчика: \(angle)") }
        return Double(angle)
    }

    deinit { IOHIDDeviceClose(device, 0); IOHIDManagerClose(manager, 0) }
}

struct LidReading: Sendable {
    var angle: Double?
    var timestamp: CFTimeInterval = 0
    var error: String?
}

final class LidAngleSensor: @unchecked Sendable {
    let latest = Mailbox(LidReading())
    private let queue = DispatchQueue(label: "duolid.sensor", qos: .userInteractive)
    // All mutable state below belongs exclusively to queue.
    private var device: LidAngleDevice?
    private var timer: DispatchSourceTimer?
    private var nextReconnect: CFTimeInterval = 0

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
            source.setEventHandler { [weak self] in self?.poll() }
            timer = source
            source.resume()
        }
    }
    func stop() {
        queue.async { [self] in timer?.cancel(); timer = nil; device = nil; latest.set(LidReading()) }
    }
    private func poll() {
        let now = CACurrentMediaTime()
        if device == nil && now < nextReconnect { return }
        do {
            if device == nil { device = try LidAngleDevice() }
            let angle = try device!.read()
            latest.set(LidReading(angle: angle, timestamp: now))
        } catch {
            latest.set(LidReading(error: error.localizedDescription))
            device = nil
            nextReconnect = now + 2
        }
    }
}
