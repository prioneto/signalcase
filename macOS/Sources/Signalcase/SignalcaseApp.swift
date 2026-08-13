import SwiftUI

@main
struct SignalcaseApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Signalcase", id: "main") {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1180, minHeight: 720)
                .onOpenURL { model.handleDeepLink($0) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                Divider()
                Button("Send Feedback…") { model.openFeedback() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Sync recent logs") { model.isCapturePresented = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
