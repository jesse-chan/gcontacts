import SwiftUI
import GoogleSignInSwift

struct SettingsView: View {
    @Environment(GoogleAuthService.self) private var googleAuth
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

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
                    Button("googleAuth.signOut", role: .destructive) {
                        googleAuth.signOut()
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
                Text("settings.languageNote")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("settings.title")
        .alert("error.title", isPresented: Binding(
            get: { googleAuth.errorMessage != nil },
            set: { if !$0 { googleAuth.errorMessage = nil } }
        )) {
            Button("action.ok", role: .cancel) {}
        } message: {
            Text(googleAuth.errorMessage ?? "")
        }
    }
}
