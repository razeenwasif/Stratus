import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct StratusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1020, minHeight: 680)
                .onOpenURL { url in
                    Task { await appState.handleDeepLink(url) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Navigate") {
                Button("Command Palette") {
                    appState.showCommandPalette.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Toggle Agent Drawer") {
                    withAnimation(.easeOut(duration: 0.18)) {
                        appState.toggleAgentDrawer()
                    }
                }
                .keyboardShortcut("j", modifiers: .command)

                Button("Toggle Sidebar") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        appState.sidebarCollapsed.toggle()
                    }
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Refresh Active View") {
                    Task { await appState.refreshCurrentSection() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                ForEach(NavSection.allCases) { section in
                    Button(section.title) {
                        appState.navigate(to: section)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(section.shortcutDigit)), modifiers: .command)
                }
            }
        }
    }
}
