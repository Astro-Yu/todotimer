import AppKit
import SwiftUI

@main
struct FloatingTodoTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some Scene {
        MenuBarExtra("TodoTimer", systemImage: "timer") {
            Text("FloatingTodoTimer v\(appVersion)")
                .font(.caption)

            Divider()

            Button(appDelegate.store.isPinnedExpanded ? "Unpin Expanded View (⌥Space)" : "Pin Expanded View (⌥Space)") {
                appDelegate.store.togglePinnedExpanded()
                appDelegate.panelController?.show()
            }

            Button("Copy Obsidian Markdown") {
                appDelegate.store.copyMarkdownToClipboard()
            }

            Divider()

            Button("Reset Window Position") {
                appDelegate.panelController?.resetPosition()
            }

            Divider()

            Button("Quit FloatingTodoTimer") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    lazy var store = TodoStore()
    var panelController: FloatingPanelController?
    private var hotkeyMonitor: GlobalHotkeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") {
            let code = SelfTestRunner.runAll()
            exit(code)
        }

        // Ensure agent app behavior (no Dock icon, no Cmd+Tab switcher entry)
        NSApp.setActivationPolicy(.accessory)

        let controller = FloatingPanelController(store: store)
        self.panelController = controller
        controller.show()

        // Global Hotkey: Option + Space toggles Pinned Expanded state
        self.hotkeyMonitor = GlobalHotkeyMonitor { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    self.store.togglePinnedExpanded()
                }
                self.panelController?.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.pauseAllTimers()
        store.save()
    }
}
