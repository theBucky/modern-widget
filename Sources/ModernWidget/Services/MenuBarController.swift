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

    private let statusItem: NSStatusItem
    private let panel: NSPanel
    private let glassView: NSGlassEffectView
    private let hostingView: NSHostingView<PanelRootView>
    private var outsideMonitor: Any?
    private var lastContentSize: CGSize = .zero

    init(engine: ReminderEngine, menuBarViewModel: MenuBarViewModel) {
        statusItem = NSStatusBar.system.statusItem(withLength: Layout.statusItemLength)

        var onContentSizeChange: ((CGSize) -> Void)?
        hostingView = NSHostingView(
            rootView: PanelRootView(engine: engine) { size in
                onContentSizeChange?(size)
            }
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        glassView = NSGlassEffectView()
        glassView.cornerRadius = Layout.panelCornerRadius

        panel = NSPanel(
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

        super.init()

        onContentSizeChange = { [weak self] size in
            self?.applyContentSize(size)
        }

        installIcon(viewModel: menuBarViewModel)

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

    private func installIcon(viewModel: MenuBarViewModel) {
        guard let button = statusItem.button else { return }

        let iconHost = NSHostingView(
            rootView: MenuBarIconView(viewModel: viewModel).allowsHitTesting(false)
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
        guard positionPanel(size: hostingView.fittingSize) else { return }
        panel.makeKeyAndOrderFront(nil)
        installOutsideMonitor()
    }

    private func applyContentSize(_ size: CGSize) {
        guard panel.isVisible, size != lastContentSize else { return }
        positionPanel(size: size)
    }

    @discardableResult
    private func positionPanel(size: CGSize) -> Bool {
        guard let button = statusItem.button, let buttonWindow = button.window else {
            return false
        }

        let buttonScreenRect = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        let visibleFrame = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let margin = Layout.panelSpacing
        let rawX = buttonScreenRect.midX - size.width / 2
        let clampedX = min(
            max(rawX, visibleFrame.minX + margin),
            visibleFrame.maxX - size.width - margin
        )
        let origin = NSPoint(
            x: clampedX,
            y: buttonScreenRect.minY - size.height - margin
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
            MainActor.assumeIsolated {
                self?.hidePanel()
            }
        }
    }

    private func removeOutsideMonitor() {
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
        }
        outsideMonitor = nil
    }
}

private struct PanelRootView: View {
    let engine: ReminderEngine
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        MenuBarContentView(engine: engine, onSizeChange: onSizeChange)
            .environment(\.controlActiveState, .active)
            .ignoresSafeArea()
    }
}
