import SwiftUI

@main
struct GContactsApp: App {
    @State private var contactStore = ContactStore(service: MockGoogleContactsService())
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(contactStore)
                .preferredColorScheme(appTheme.colorScheme)
        }
    }
}

