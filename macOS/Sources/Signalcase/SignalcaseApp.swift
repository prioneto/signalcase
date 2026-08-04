import SwiftUI

@main
struct SignalcaseApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1180, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Capture recent logs") { model.isCapturePresented = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

