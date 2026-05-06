import SwiftUI
import GoogleSignIn

@main
struct GContactsApp: App {
    @State private var contactStore = ContactStore(service: MockGoogleContactsService())
    @State private var googleAuthService = GoogleAuthService()
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(contactStore)
                .environment(googleAuthService)
                .preferredColorScheme(appTheme.colorScheme)
                .onAppear {
                    googleAuthService.restorePreviousSignIn()
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
