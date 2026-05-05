import SwiftUI

struct SettingsView: View {
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
                LabeledContent("settings.authStatus", value: String(localized: "settings.mockMode"))
                Text("settings.googleNote")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("settings.language") {
                Text("settings.languageNote")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("settings.title")
    }
}

