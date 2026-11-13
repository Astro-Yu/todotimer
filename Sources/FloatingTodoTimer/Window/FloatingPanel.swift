import AppKit
import Combine
import QuartzCore
import SwiftUI

public final class FloatingPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.animationBehavior = .none
        self.isReleasedWhenClosed = false
    }

    public override var canBecomeKey: Bool {
        true
    }

    public override var canBecomeMain: Bool {
        false
    }
}

@MainActor
public final class FloatingPanelController: NSObject, NSWindowDelegate {
    // Both Compact and Expanded share the exact same width (300px) so neither left nor right edge shifts.
    public static let compactSize = NSSize(width: 300, height: 44)
    public static let expandedSize = NSSize(width: 300, height: 280)
    public static let hoverExpandDelaySeconds: TimeInterval = 0.5

    private static let posXKey = "FloatingTodoTimer.panelTopLeftX"
    private static let posYKey = "FloatingTodoTimer.panelTopLeftY"
    private static let hasSavedPosKey = "FloatingTodoTimer.hasSavedPosition"

    public let panel: FloatingPanel
    private var hostingView: FirstMouseHostingView<WidgetContentView>?
    private let store: TodoStore
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var isProgrammaticFrameChange = false
    private var hoverDelayTask: Task<Void, Never>?
    private var hoverWatchdogTimer: Timer?
    /// Anchor top-left point in screen coordinates so rapid expand/collapse animations never drift vertically.
    private var anchoredTopLeft: NSPoint = .zero

    public init(store: TodoStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults

        let initialRect = NSRect(origin: .zero, size: Self.compactSize)
        self.panel = FloatingPanel(contentRect: initialRect)
        super.init()

        self.panel.delegate = self

        let rootView = WidgetContentView(
            store: store,
            onRequestTextFocus: { [weak self] in
                self?.focusPanelForTextEditing()
            },
            onReleaseTextFocus: { [weak self] in
                self?.releaseKeyFocus()
            }
        )

        let hosting = FirstMouseHostingView(
            rootView: rootView,
            onMouseEntered: { [weak self] in
                self?.handleMouseEntered()
            },
            onMouseExited: { [weak self] in
                self?.handleMouseExited()
            }
        )
        hosting.sizingOptions = []
        hosting.frame = initialRect
        hosting.autoresizingMask = [.width, .height]
        self.hostingView = hosting
        self.panel.contentView = hosting

        restoreOrDefaultPosition()
        observeExpansionState()
    }

    public func show() {
        panel.orderFrontRegardless()
    }

    public func resetPosition() {
        defaults.removeObject(forKey: Self.hasSavedPosKey)
        defaults.removeObject(forKey: Self.posXKey)
        defaults.removeObject(forKey: Self.posYKey)
        applyDefaultPosition()
        saveCurrentTopLeftPosition()
        panel.orderFrontRegardless()
    }

    public func focusPanelForTextEditing() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func releaseKeyFocus() {
        panel.makeFirstResponder(nil)
        panel.resignKey()
    }

    // MARK: - Hover Delay (0.5s) & Smooth Collapse on Mouse Exit

    private func handleMouseEntered() {
        hoverDelayTask?.cancel()
        guard !store.isHovered else { return }

        hoverDelayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.hoverExpandDelaySeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }

            let mouseLocation = NSEvent.mouseLocation
            if self.panel.frame.insetBy(dx: -2, dy: -2).contains(mouseLocation) {
                withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.18)) {
                    self.store.isHovered = true
                }
                self.startHoverWatchdog()
            }
        }
    }

    private func handleMouseExited() {
        hoverDelayTask?.cancel()
        hoverDelayTask = nil

        let mouseLocation = NSEvent.mouseLocation
        if panel.frame.insetBy(dx: 1, dy: 1).contains(mouseLocation) {
            return
        }

        collapseFromHoverImmediately()
    }

    private func startHoverWatchdog() {
        hoverWatchdogTimer?.invalidate()
        hoverWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.store.isHovered {
                    self.stopHoverWatchdog()
                    return
                }
                let mouseLocation = NSEvent.mouseLocation
                if !self.panel.frame.insetBy(dx: -2, dy: -2).contains(mouseLocation) {
                    self.collapseFromHoverImmediately()
                }
            }
        }
    }

    private func stopHoverWatchdog() {
        hoverWatchdogTimer?.invalidate()
        hoverWatchdogTimer = nil
    }

    private func collapseFromHoverImmediately() {
        hoverDelayTask?.cancel()
        hoverDelayTask = nil
        stopHoverWatchdog()

        if store.isEditingText {
            store.isEditingText = false
        }
        releaseKeyFocus()

        if store.isHovered {
            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.16)) {
                store.isHovered = false
            }
        }
    }

    // MARK: - Smooth Non-Blocking Expand / Collapse Animation

    private func observeExpansionState() {
        Publishers.CombineLatest(
            store.$isHovered,
            store.$isPinnedExpanded
        )
        .map { isHovered, isPinned in
            isHovered || isPinned
        }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak self] expanded in
            self?.animatePanelSize(expanded: expanded)
        }
        .store(in: &cancellables)
    }

    private func animatePanelSize(expanded: Bool) {
        let targetSize = expanded ? Self.expandedSize : Self.compactSize
        let duration: TimeInterval = expanded ? 0.18 : 0.15

        // Use anchoredTopLeft so even if user moves mouse in/out mid-animation, top edge never drifts
        if !isProgrammaticFrameChange {
            anchoredTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        }

        var newFrame = NSRect(
            x: anchoredTopLeft.x,
            y: anchoredTopLeft.y - targetSize.height,
            width: targetSize.width,
            height: targetSize.height
        )

        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if newFrame.maxX > visible.maxX {
                newFrame.origin.x = visible.maxX - newFrame.width - 8
            }
            if newFrame.minX < visible.minX {
                newFrame.origin.x = visible.minX + 8
            }
            if newFrame.minY < visible.minY {
                newFrame.origin.y = visible.minY + 8
            }
            anchoredTopLeft = NSPoint(x: newFrame.minX, y: newFrame.maxY)
        }

        isProgrammaticFrameChange = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            // Fast ease-out cubic bezier ("슉슉" snappy slide feel)
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isProgrammaticFrameChange = false
                self.panel.invalidateShadow()
            }
        }

        if !expanded {
            releaseKeyFocus()
        }
    }

    // MARK: - Position Persistence

    private func restoreOrDefaultPosition() {
        let size = store.isExpanded ? Self.expandedSize : Self.compactSize
        if defaults.bool(forKey: Self.hasSavedPosKey) {
            let topLeftX = defaults.double(forKey: Self.posXKey)
            let topLeftY = defaults.double(forKey: Self.posYKey)
            let candidateFrame = NSRect(
                x: topLeftX,
                y: topLeftY - size.height,
                width: size.width,
                height: size.height
            )
            if isFrameVisibleOnAnyScreen(candidateFrame) {
                isProgrammaticFrameChange = true
                panel.setFrame(candidateFrame, display: true)
                anchoredTopLeft = NSPoint(x: candidateFrame.minX, y: candidateFrame.maxY)
                isProgrammaticFrameChange = false
                return
            }
        }
        applyDefaultPosition()
        saveCurrentTopLeftPosition()
    }

    private func applyDefaultPosition() {
        let size = store.isExpanded ? Self.expandedSize : Self.compactSize
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenFrame.maxX - size.width - 24,
            y: screenFrame.maxY - size.height - 24
        )
        let rect = NSRect(origin: origin, size: size)
        isProgrammaticFrameChange = true
        panel.setFrame(rect, display: true)
        anchoredTopLeft = NSPoint(x: rect.minX, y: rect.maxY)
        isProgrammaticFrameChange = false
    }

    private func isFrameVisibleOnAnyScreen(_ frame: NSRect) -> Bool {
        for screen in NSScreen.screens {
            if screen.visibleFrame.intersects(frame.insetBy(dx: 20, dy: 10)) {
                return true
            }
        }
        return false
    }

    private func saveCurrentTopLeftPosition() {
        let frame = panel.frame
        anchoredTopLeft = NSPoint(x: frame.minX, y: frame.maxY)
        defaults.set(Double(frame.minX), forKey: Self.posXKey)
        defaults.set(Double(frame.maxY), forKey: Self.posYKey)
        defaults.set(true, forKey: Self.hasSavedPosKey)
    }

    // MARK: - NSWindowDelegate

    public func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticFrameChange else { return }
        saveCurrentTopLeftPosition()
    }

    public func windowDidResignKey(_ notification: Notification) {
        if store.isEditingText {
            store.isEditingText = false
        }
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    private let onMouseEntered: () -> Void
    private let onMouseExited: () -> Void
    private var trackingArea: NSTrackingArea?

    init(
        rootView: Content,
        onMouseEntered: @escaping () -> Void,
        onMouseExited: @escaping () -> Void
    ) {
        self.onMouseEntered = onMouseEntered
        self.onMouseExited = onMouseExited
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("init(rootView:) has not been implemented")
    }

    @available(*, unavailable)
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseEntered()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExited()
    }
}
