import AppKit

@main
struct DuoLidAnimationApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--sensor") {
            do {
                let sensor = try LidAngleDevice()
                let count = CommandLine.arguments.last.flatMap(Int.init) ?? 100
                for _ in 0..<max(1, count) {
                    print(String(format: "Lid angle: %.1f°", try sensor.read()))
                    Thread.sleep(forTimeInterval: 0.05)
                }
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--self-test") {
            do { try SelfTest.run() }
            catch { fputs("SELF TEST FAILED: \(error)\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
