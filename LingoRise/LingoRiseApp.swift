import SwiftUI

@main
struct LingoRiseApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environment(\.locale, Locale(identifier: AppLocalization.localeIdentifier(for: appState.appLanguage)))
                .preferredColorScheme(appState.preferredColorScheme)
                .id(appState.appLanguage)
        }
    }
}
