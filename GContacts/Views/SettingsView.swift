import SwiftUI
import GoogleSignInSwift

struct SettingsView: View {
    @Environment(GoogleAuthService.self) private var googleAuth
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .system
    @State private var isConfirmingDisconnect = false

    var body: some View {
        Form {
            Section("settings.appearance") {
                Picker("settings.theme", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.localizedTitle).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("settings.google") {
                if googleAuth.isRestoring {
                    ProgressView("googleAuth.restoring")
                } else if let user = googleAuth.user {
                    LabeledContent("settings.authStatus", value: String(localized: "googleAuth.signedIn"))
                    if let name = user.fullName {
                        LabeledContent("googleAuth.name", value: name)
                    }
                    if let email = user.email {
                        LabeledContent("googleAuth.email", value: email)
                    }
                    Button("googleAuth.disconnect", role: .destructive) {
                        isConfirmingDisconnect = true
                    }
                    .disabled(googleAuth.isDisconnecting)

                    if googleAuth.isDisconnecting {
                        ProgressView("googleAuth.disconnecting")
                    }
                } else {
                    LabeledContent("settings.authStatus", value: String(localized: "googleAuth.signedOut"))

                    GoogleSignInButton {
                        googleAuth.signIn()
                    }
                    .disabled(googleAuth.isSigningIn || !googleAuth.isConfigured)

                    if googleAuth.isSigningIn {
                        ProgressView("googleAuth.signingIn")
                    }
                }

                if !googleAuth.isConfigured {
                    Text("googleAuth.configurationNote")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("settings.language") {
                Picker("settings.languageSelection", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(String(localized: language.localizedTitle)).tag(language)
                    }
                }
                .pickerStyle(.menu)

                Text("settings.languageNote")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("settings.title")
        .confirmationDialog(
            "googleAuth.disconnectTitle",
            isPresented: $isConfirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button("googleAuth.disconnectConfirm", role: .destructive) {
                Task {
                    await googleAuth.signOutAndDisconnect()
                }
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("googleAuth.disconnectMessage")
        }
        .alert("error.title", isPresented: Binding(
            get: { googleAuth.errorMessage != nil },
            set: { if !$0 { googleAuth.clearError() } }
        )) {
            Button("action.ok", role: .cancel) {}
        } message: {
            Text(googleAuth.errorMessage ?? "")
        }
    }
}
