import AppKit
import MetalKit

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayWindowController {
    let window: NSWindow
    let view: MTKView
    let displayID: CGDirectDisplayID
    let pixelWidth: Int
    let pixelHeight: Int
    private(set) var visible = false

    init(renderer: MetalRenderer) throws {
        guard let screen = NSScreen.screens.first(where: {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) != 0
        }), let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw AppError("Активный встроенный дисплей MacBook не найден")
        }
        displayID = id.uint32Value
        pixelWidth = Int(screen.frame.width * screen.backingScaleFactor)
        pixelHeight = Int(screen.frame.height * screen.backingScaleFactor)
        window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.hidesOnDeactivate = false
        window.sharingType = .none // Additional hint; application exclusion is the recursion guarantee.
        view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.framebufferOnly = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.autoResizeDrawable = true
        view.drawableSize = CGSize(width: pixelWidth, height: pixelHeight)
        view.isPaused = true // Main-thread timer drives both angle integration and rendering, no redundant loop.
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.delegate = renderer
        window.contentView = view
        // Realize the window without exposing it, so SCShareableContent can identify this app.
        window.alphaValue = 0
        window.orderFrontRegardless()
    }
    func matchesCurrentScreen() -> Bool {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else { return false }
        return screen.frame == window.frame
            && Int(screen.frame.width * screen.backingScaleFactor) == pixelWidth
            && Int(screen.frame.height * screen.backingScaleFactor) == pixelHeight
    }
    func render() {
        if !visible {
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        view.draw()
        window.alphaValue = 1
        visible = true
    }
    func hide() { window.orderOut(nil); visible = false }
    func close() { hide(); window.close() }
}
