import AppKit
import CoreGraphics
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private let stateItem = NSMenuItem(title: "Запуск…", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Приостановить", action: #selector(toggle), keyEquivalent: "")
    private var sensor = LidAngleSensor()
    private var capture: ScreenCaptureManager?
    private var renderer: MetalRenderer?
    private var overlay: OverlayWindowController?
    private var animation = AnimationController(config: AnimationConfig())
    private var timer: Timer?
    private var enabled = true
    private var generation = 0
    private var lastMenuUpdate: Double = 0
    private var captureStarted: Double = 0
    private var hasReceivedFrame = false
    private var suspended = false
    private var wakeDeadline: Double = 0
    private var synchronizeAngle = true
    private var recoveringCapture = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "◩ Duo"
        let menu = NSMenu()
        menu.addItem(stateItem)
        menu.addItem(.separator())
        toggleItem.target = self
        menu.addItem(toggleItem)
        add(menu, "Запустить / повторить подключение", #selector(retry))
        add(menu, "Настроить разрешение записи экрана…", #selector(openPermission))
        menu.addItem(.separator())
        add(menu, "Открыть параметры анимации…", #selector(editConfig))
        add(menu, "Применить параметры", #selector(retry))
        add(menu, "Начинать складывание с текущего угла", #selector(calibrate))
        menu.addItem(.separator())
        add(menu, "Завершить DuoLidAnimation", #selector(quit))
        status.menu = menu
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(woke), name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        Task { await restart(requestPermission: true) }
    }
    private func add(_ menu: NSMenu, _ title: String, _ selector: Selector) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }
    private func tearDown() {
        generation += 1
        suspended = false; wakeDeadline = 0; recoveringCapture = false; synchronizeAngle = true
        timer?.invalidate(); timer = nil
        sensor.stop()
        overlay?.close(); overlay = nil
        renderer = nil
        if let old = capture { Task { await old.stop() } }
        capture = nil
    }
    private func restart(requestPermission: Bool) async {
        tearDown()
        guard enabled else { return }
        let token = generation
        stateItem.title = "Подключение…"
        do {
            let config = try AnimationConfig.load()
            animation = AnimationController(config: config)
            sensor.start()
            let accessGranted = CGPreflightScreenCaptureAccess()
                || (requestPermission && CGRequestScreenCaptureAccess())
            guard accessGranted else {
                stateItem.title = "Нужно разрешение записи экрана"
                if requestPermission {
                    showMessage("Разрешите запись экрана", "В Системных настройках → Конфиденциальность и безопасность → Запись экрана и системного аудио разрешите DuoLidAnimation. Затем выберите «Запустить / повторить подключение» или перезапустите приложение. Звук не захватывается; кадры не сохраняются.")
                }
                return
            }
            let gpu = try MetalRenderer(config: config)
            let window = try OverlayWindowController(renderer: gpu)
            let recorder = ScreenCaptureManager()
            renderer = gpu; overlay = window; capture = recorder
            try await recorder.start(displayID: window.displayID, pixelWidth: window.pixelWidth, pixelHeight: window.pixelHeight)
            guard token == generation, enabled else { await recorder.stop(); window.close(); return }
            window.hide()
            captureStarted = CACurrentMediaTime()
            hasReceivedFrame = false
            let tick = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer = tick
            RunLoop.main.add(tick, forMode: .common)
            NSLog("DuoLidAnimation ready")
            if CommandLine.arguments.contains("--capture-test") {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    if CommandLine.arguments.contains("--wake-test") {
                        self?.checkWakeLifecycle()
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                    self?.finishCaptureTest()
                }
            }
        } catch {
            guard token == generation else { return }
            tearDown()
            stateItem.title = "Ошибка: \(error.localizedDescription)"
            NSLog("Startup error: %@", error.localizedDescription)
            showMessage("Не удалось запустить эффект", error.localizedDescription)
        }
    }
    private func tick() {
        guard !suspended, let capture, let renderer, let overlay else { return }
        let now = CACurrentMediaTime()
        if wakeDeadline > 0 && !recoveringCapture && capture.failure.get() != nil {
            recoverCapture()
        }
        if let error = renderer.error ?? (wakeDeadline == 0 ? capture.failure.get() : nil) {
            tearDown()
            stateItem.title = "Ошибка: \(error) — повторите подключение"
            return
        }
        let reading = sensor.latest.get()
        guard let angle = reading.angle, now - reading.timestamp < 0.35 else {
            if now >= wakeDeadline { overlay.hide() }
            stateItem.title = reading.error ?? "Ожидание реального датчика…"
            return
        }
        if synchronizeAngle {
            animation.synchronize(angle: angle, now: now)
            synchronizeAngle = false
        }
        let progress = animation.update(angle: angle, now: now)
        let freshFrame = capture.latest.get()
        // During wake, keep the last real desktop frame until capture has resumed.
        let frame = freshFrame ?? (now < wakeDeadline ? renderer.frame : nil)
        if wakeDeadline > 0 && now >= wakeDeadline {
            if freshFrame == nil && !recoveringCapture { recoverCapture() }
            else if freshFrame != nil { wakeDeadline = 0 }
        }
        renderer.frame = frame
        hasReceivedFrame = hasReceivedFrame || frame != nil
        if !hasReceivedFrame && now - captureStarted > 8 {
            tearDown()
            stateItem.title = "Нет кадров ScreenCaptureKit — повторите подключение"
            return
        }
        if now - lastMenuUpdate > 0.3 {
            status.button?.title = String(format: "◩ %.0f°", angle)
            stateItem.title = String(format: "Датчик %.1f° · %@", angle, frame == nil ? "ждём кадр" : "готово")
            lastMenuUpdate = now
        }
        renderer.progress = progress
        if frame != nil && progress > 0.0005 { overlay.render() } else { overlay.hide() }
    }
    private func checkWakeLifecycle() {
        let oldWindow = overlay
        let oldCapture = capture
        let oldRenderer = renderer
        let oldGeneration = generation
        let oldProgress = animation.progress
        sleeping()
        precondition(overlay === oldWindow && renderer === oldRenderer && capture === oldCapture)
        precondition(generation == oldGeneration && animation.progress == oldProgress)
        woke()
        woke() // Duplicate notifications must not restart the stream.
        screenChanged()
        precondition(overlay === oldWindow && renderer === oldRenderer && capture === oldCapture)
        precondition(generation == oldGeneration && animation.progress == oldProgress)
        NSLog("PASS: simulated sleep/wake preserves window, GPU, capture and pose; duplicate wake ignored")
    }
    private func finishCaptureTest() {
        let reading = sensor.latest.get()
        let frame = capture?.latest.get()
        // Exercise the same texture-cache/render path even if the real lid is fully open.
        // Progress still comes only from the physical sensor.
        if let frame, let renderer, let overlay {
            renderer.frame = frame
            overlay.render()
        }
        let success = frame != nil && reading.angle != nil && (renderer?.submittedFrames ?? 0) > 0 && capture?.failure.get() == nil
        let report = "Capture test: \(success ? "PASS" : "FAIL")\nReal angle: \(reading.angle.map(String.init(describing:)) ?? "none")\nFrame: \(frame.map { "\(CVPixelBufferGetWidth($0.buffer))x\(CVPixelBufferGetHeight($0.buffer))" } ?? "none")\nGPU submitted frames: \(renderer?.submittedFrames ?? 0)\nOwn application excluded: true (guarded at stream creation)\n"
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("capture-test.log")
        try? report.write(to: url, atomically: true, encoding: .utf8)
        NSLog("%@", report)
        overlay?.hide()
        NSApp.terminate(nil)
    }
    @objc private func retry() { enabled = true; toggleItem.title = "Приостановить"; Task { await restart(requestPermission: true) } }
    @objc private func toggle() {
        enabled.toggle()
        toggleItem.title = enabled ? "Приостановить" : "Продолжить"
        if enabled { Task { await restart(requestPermission: false) } }
        else { tearDown(); stateItem.title = "Приостановлено"; status.button?.title = "◩ Duo ⏸" }
    }
    @objc private func sleeping() {
        guard enabled, !suspended else { return }
        suspended = true
        sensor.stop()
        // Keep the window, drawable, pipeline and last physical-angle pose in place.
        // Destroying them exposed the normal desktop while SCStream was recreated.
        stateItem.title = "Сон — состояние анимации сохранено"
    }
    @objc private func woke() {
        guard enabled, suspended else { return } // Coalesce display/system wake notifications.
        suspended = false
        wakeDeadline = CACurrentMediaTime() + 3
        synchronizeAngle = true
        sensor.start()
        if capture == nil { Task { await restart(requestPermission: false) } }
        else if capture?.failure.get() != nil { recoverCapture() }
    }
    @objc private func screenChanged() {
        guard enabled, !suspended else { return }
        // Wake commonly emits this notification even when the display geometry is unchanged.
        if let overlay, overlay.matchesCurrentScreen() { return }
        Task { await restart(requestPermission: false) }
    }
    private func recoverCapture() {
        guard !recoveringCapture, let window = overlay else { return }
        recoveringCapture = true
        let token = generation
        let old = capture
        Task { @MainActor [weak self] in
            guard let self else { return }
            await old?.stop()
            guard token == generation else { return }
            let recorder = ScreenCaptureManager()
            do {
                try await recorder.start(displayID: window.displayID, pixelWidth: window.pixelWidth, pixelHeight: window.pixelHeight)
                guard token == generation else { await recorder.stop(); return }
                capture = recorder
                recoveringCapture = false
                captureStarted = CACurrentMediaTime()
                hasReceivedFrame = false
                wakeDeadline = captureStarted + 3
                NSLog("Capture recovered; existing overlay and animation preserved")
            } catch {
                guard token == generation else { return }
                recoveringCapture = false
                tearDown()
                stateItem.title = "Не удалось восстановить захват: \(error.localizedDescription)"
            }
        }
    }
    @objc private func openPermission() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    @objc private func editConfig() {
        do { _ = try AnimationConfig.load(); NSWorkspace.shared.open(AnimationConfig.userURL) }
        catch { showMessage("Ошибка параметров", error.localizedDescription) }
    }
    @objc private func calibrate() {
        guard let angle = sensor.latest.get().angle else { return }
        do {
            var config = try AnimationConfig.load()
            config.startAngle = angle
            try config.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: AnimationConfig.userURL, options: .atomic)
            Task { await restart(requestPermission: false) }
        } catch { showMessage("Ошибка калибровки", error.localizedDescription) }
    }
    private func showMessage(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "Понятно")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { tearDown() }
}
