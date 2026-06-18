import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private enum Layout {
        static let statusItemLength: CGFloat = 22
        static let iconSize: CGFloat = 22
        static let panelSpacing: CGFloat = 6
        static let panelCornerRadius: CGFloat = 10
        static let dimmedIconAlpha: CGFloat = 0.5
    }

    private let engine: ReminderEngine
    private let usageStore: CodingUsageStore
    private var outsideMonitor: Any?
    private var lastContentSize: CGSize = .zero

    private lazy var statusItem = NSStatusBar.system.statusItem(
        withLength: Layout.statusItemLength
    )

    private lazy var hostingView: NSView = {
        let view = NSHostingView(
            rootView: MenuBarContentView(engine: engine, usageStore: usageStore) {
                [weak self] size in
                self?.applyContentSize(size)
            }
            .environment(\.controlActiveState, .active)
            .ignoresSafeArea()
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var panel: NSPanel = {
        let glassView = NSGlassEffectView()
        glassView.cornerRadius = Layout.panelCornerRadius

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary,
        ]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        panel.contentView = glassView
        glassView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: glassView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
        ])
        return panel
    }()

    init(
        engine: ReminderEngine = ReminderEngine(), usageStore: CodingUsageStore = CodingUsageStore()
    ) {
        self.engine = engine
        self.usageStore = usageStore
        super.init()
        installIcon()
        installObservers()
    }

    private func installObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )

        if let statusWindow = statusItem.button?.window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(statusWindowDidChangeOcclusion),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: statusWindow
            )
        }
    }

    private func installIcon() {
        guard let button = statusItem.button else { return }

        let iconHost = NSHostingView(
            rootView: MenuBarIconView(engine: engine).allowsHitTesting(false)
        )
        iconHost.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(iconHost)
        NSLayoutConstraint.activate([
            iconHost.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            iconHost.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconHost.widthAnchor.constraint(equalToConstant: Layout.iconSize),
            iconHost.heightAnchor.constraint(equalToConstant: Layout.iconSize),
        ])

        button.target = self
        button.action = #selector(togglePanel)
    }

    @objc private func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    @objc private func panelDidResignKey() {
        hidePanel()
    }

    @objc private func statusWindowDidChangeOcclusion() {
        guard let window = statusItem.button?.window else { return }
        let visible = window.occlusionState.contains(.visible)
        statusItem.button?.animator().alphaValue = visible ? 1.0 : Layout.dimmedIconAlpha
    }

    private func showPanel() {
        hostingView.layoutSubtreeIfNeeded()
        guard positionPanel(size: hostingView.fittingSize) else {
            return
        }
        panel.makeKeyAndOrderFront(nil)
        installOutsideMonitor()
    }

    private func applyContentSize(_ size: CGSize) {
        guard panel.isVisible, size != lastContentSize else { return }
        if !positionPanel(size: size) {
            hidePanel()
        }
    }

    private func positionPanel(size: CGSize) -> Bool {
        guard let button = statusItem.button, let buttonWindow = button.window else {
            return false
        }

        let buttonScreenRect = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        guard let visibleFrame = buttonWindow.screen?.visibleFrame else {
            return false
        }

        let origin = MenuBarPanelPlacement.origin(
            contentSize: size,
            statusItemFrame: buttonScreenRect,
            visibleFrame: visibleFrame,
            spacing: Layout.panelSpacing
        )
        panel.setContentSize(size)
        panel.setFrameOrigin(origin)
        lastContentSize = size
        return true
    }

    private func hidePanel() {
        panel.orderOut(nil)
        removeOutsideMonitor()
    }

    private func installOutsideMonitor() {
        removeOutsideMonitor()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hidePanel()
            }
        }
    }

    private func removeOutsideMonitor() {
        guard let outsideMonitor else { return }
        NSEvent.removeMonitor(outsideMonitor)
        self.outsideMonitor = nil
    }
}
