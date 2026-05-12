import SwiftUI
import GoogleSignIn

@main
struct GContactsApp: App {
    @State private var contactStore: ContactStore
    @State private var googleAuthService: GoogleAuthService
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .system

    init() {
        let authService = GoogleAuthService()
        _googleAuthService = State(initialValue: authService)
        _contactStore = State(initialValue: ContactStore(service: GooglePeopleContactsService(authService: authService)))
    }

    var body: some Scene {
        WindowGroup {
            StartupAuthGateView()
                .environment(contactStore)
                .environment(googleAuthService)
                .preferredColorScheme(appTheme.colorScheme)
                .environment(\.locale, appLanguage.locale)
                .onAppear {
                    googleAuthService.restorePreviousSignIn()
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
