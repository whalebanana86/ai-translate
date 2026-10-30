import AppKit
import TranslateCore

/// 사용자가 고른 화면 영역.
struct ScreenSelection {
    var displayID: CGDirectDisplayID
    /// 디스플레이 로컬 좌표 (왼쪽 위 원점, 포인트)
    var rect: CGRect
    /// 화면 배율 (Retina 2)
    var scale: CGFloat
    /// 전역 AppKit 좌표. 결과창 위치를 잡을 때 쓴다
    var globalRect: CGRect
}

/// 모든 화면을 덮는 선택 오버레이.
@MainActor
final class SelectionOverlayController {
    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<ScreenSelection?, Never>?

    /// 오버레이를 띄우고 사용자가 고른 영역을 돌려준다. ESC·오른쪽 클릭·너무 작은 선택이면 nil.
    func selectRegion() async -> ScreenSelection? {
        guard continuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            showPanels()
        }
    }

    private func showPanels() {
        panels = NSScreen.screens.map { screen in
            let panel = SelectionPanel(screen: screen)
            panel.selectionView.onFinish = { [weak self] globalRect in self?.finish(globalRect, on: screen) }
            panel.selectionView.onCancel = { [weak self] in self?.finish(nil, on: screen) }
            panel.orderFrontRegardless()
            return panel
        }
        // 마우스가 있는 화면의 패널이 키 입력(ESC)을 받게 한다
        let mouse = NSEvent.mouseLocation
        let keyPanel = panels.first { $0.frame.contains(mouse) } ?? panels.first
        keyPanel?.makeKey()
        keyPanel?.makeFirstResponder(keyPanel?.selectionView)
    }

    private func finish(_ globalRect: CGRect?, on screen: NSScreen) {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels = []
        let selection = globalRect.flatMap { makeSelection($0, on: screen) }
        continuation?.resume(returning: selection)
        continuation = nil
    }

    private func makeSelection(_ globalRect: CGRect, on screen: NSScreen) -> ScreenSelection? {
        guard
            let clamped = ScreenGeometry.clamp(globalRect, to: screen.frame),
            ScreenGeometry.isSelectable(clamped),
            let displayID = screen.displayID
        else { return nil }
        return ScreenSelection(
            displayID: displayID,
            rect: ScreenGeometry.displayLocalRect(clamped, screenFrame: screen.frame),
            scale: screen.backingScaleFactor,
            globalRect: clamped
        )
    }
}

/// 화면 하나를 덮는 투명 패널. 앱을 활성화하지 않아 원래 앱의 포커스를 빼앗지 않는다.
final class SelectionPanel: NSPanel {
    let selectionView: SelectionView

    init(screen: NSScreen) {
        selectionView = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        contentView = selectionView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

/// 화면을 어둡게 덮고 드래그한 영역만 밝게 보여준다.
final class SelectionView: NSView {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: CGPoint?
    private var current: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        start = point
        current = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start, let window else { return }
        let local = ScreenGeometry.selectionRect(from: start, to: convert(event.locationInWindow, from: nil))
        self.start = nil
        current = nil
        onFinish?(window.convertToScreen(convert(local, to: nil)))
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        // 53: ESC
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        guard let start, let current else { return }
        let rect = ScreenGeometry.selectionRect(from: start, to: current)
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
