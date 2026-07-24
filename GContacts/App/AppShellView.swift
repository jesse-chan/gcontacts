import GoogleSignInSwift
import SwiftUI
import UIKit

enum AppTab: Hashable {
    case contacts
    case labels
    case settings
}

struct ContactLabelSelection: Equatable {
    var id: String?
    var name: String

    static let all = ContactLabelSelection(id: nil, name: String(localized: "labels.all"))
}

struct AppShellView: View {
    @Environment(ContactStore.self) private var contactStore
    @Environment(GoogleAuthService.self) private var googleAuthService
    @Environment(\.locale) private var locale
    @State private var selectedTab: AppTab = .contacts
    @State private var selectedLabel = ContactLabelSelection.all
    @State private var contactListScrollToTopTrigger = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ContactsListView(
                    selectedLabel: $selectedLabel,
                    scrollToTopTrigger: contactListScrollToTopTrigger
                )
            }
            .id("contacts-\(locale.identifier)")
            .tabItem {
                Label("tab.contacts", systemImage: "person.crop.circle")
            }
            .tag(AppTab.contacts)

            NavigationStack {
                LabelsView()
            }
            .id("labels-\(locale.identifier)")
            .tabItem {
                Label("tab.labels", systemImage: "tag")
            }
            .tag(AppTab.labels)

            NavigationStack {
                SettingsView()
            }
            .id("settings-\(locale.identifier)")
            .tabItem {
                Label("tab.settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .onChange(of: googleAuthService.user) { _, user in
            Task {
                if user == nil {
                    contactStore.clear()
                    selectedLabel = .all
                } else {
                    await contactStore.load()
                }
            }
        }
        .onChange(of: contactStore.labels) { _, labels in
            guard let selectedLabelID = selectedLabel.id else { return }
            if let label = labels.first(where: { $0.id == selectedLabelID }) {
                selectedLabel = ContactLabelSelection(id: label.id, name: label.name)
            } else {
                selectedLabel = .all
            }
        }
        .task {
            if googleAuthService.user != nil && contactStore.contacts.isEmpty && contactStore.labels.isEmpty {
                await contactStore.load()
            }
        }
    }
}

struct StartupAuthGateView: View {
    @Environment(GoogleAuthService.self) private var googleAuthService
    @State private var isShowingSignInFailure = false
    @State private var signInFailureTitle = ""
    @State private var signInFailureMessage = ""
    @State private var shouldRetrySignInAfterAlert = false

    var body: some View {
        Group {
            if googleAuthService.user != nil {
                AppShellView()
            } else if googleAuthService.isRestoring || !googleAuthService.didRestorePreviousSignIn {
                ProgressView(SystemAuthLocalization.string("googleAuth.restoring"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            } else {
                GoogleRequiredSignInView {
                    googleAuthService.signIn()
                }
            }
        }
        .onChange(of: googleAuthService.errorMessage) { _, message in
            presentSignInFailureIfNeeded(message)
        }
        .onChange(of: googleAuthService.isSigningIn) { _, isSigningIn in
            guard !isSigningIn else { return }
            presentSignInFailureIfNeeded(googleAuthService.errorMessage)
        }
        .onAppear {
            presentSignInFailureIfNeeded(googleAuthService.errorMessage)
        }
        .alert(signInFailureTitle, isPresented: $isShowingSignInFailure) {
            Button(SystemAuthLocalization.string("action.ok"), role: .cancel) {
                guard shouldRetrySignInAfterAlert else { return }
                shouldRetrySignInAfterAlert = false

                Task { @MainActor in
                    // Let the system alert finish dismissing before presenting the
                    // authentication browser again.
                    try? await Task.sleep(for: .milliseconds(350))
                    googleAuthService.signIn()
                }
            }
        } message: {
            Text(signInFailureMessage)
        }
    }

    private func presentSignInFailureIfNeeded(_ message: String?) {
        guard
            googleAuthService.user == nil,
            let message,
            !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        let key = googleAuthService.errorMessageKey
        if key == "googleAuth.contactsPermissionRequired" {
            signInFailureTitle = SystemAuthLocalization.string("googleAuth.contactsPermissionRequiredTitle")
            shouldRetrySignInAfterAlert = true
        } else {
            signInFailureTitle = SystemAuthLocalization.string("error.title")
            shouldRetrySignInAfterAlert = false
        }
        if let key {
            signInFailureMessage = SystemAuthLocalization.string(key)
        } else {
            signInFailureMessage = message
        }
        googleAuthService.clearError()
        isShowingSignInFailure = true
    }
}

private struct GoogleRequiredSignInView: View {
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text(SystemAuthLocalization.string("googleAuth.requiredTitle"))
                    .font(.title2.weight(.bold))

                Text(SystemAuthLocalization.string("googleAuth.requiredMessage"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            GoogleSignInButton(action: onSignIn)
                .frame(maxWidth: 280)
                .environment(\.locale, SystemAuthLocalization.locale)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

private enum SystemAuthLocalization {
    static var locale: Locale {
        Locale(identifier: localizationIdentifier)
    }

    static func string(_ key: String) -> String {
        guard
            let path = Bundle.main.path(forResource: localizationIdentifier, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return NSLocalizedString(key, comment: "")
        }
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    private static var localizationIdentifier: String {
        let preferredLanguage = Locale.preferredLanguages.first ?? Locale.current.identifier
        return preferredLanguage.lowercased().hasPrefix("zh") ? "zh-Hant" : "en"
    }
}

#Preview {
    StartupAuthGateView()
        .environment(ContactStore(service: MockGoogleContactsService()))
        .environment(GoogleAuthService())
}
