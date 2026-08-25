import SwiftUI

@main
@MainActor
struct MaroonCompassApp: App {
    @State private var store = AppStore()

    init() {
        MaroonCompassShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(AppTheme.accent)
        }
    }
}
