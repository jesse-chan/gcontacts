import Foundation
import GoogleSignIn
import UIKit

@MainActor
@Observable
final class GoogleAuthService {
    private let contactsScope = "https://www.googleapis.com/auth/contacts"
    private let clientIDMarkerKey = "googleAuth.configuredClientID"
    private let defaults: UserDefaults

    private(set) var user: GoogleSignedInUser?
    private(set) var isRestoring = false
    private(set) var isSigningIn = false
    private(set) var isDisconnecting = false
    private(set) var didRestorePreviousSignIn = false
    private(set) var errorMessageKey: String?
    var errorMessage: String?

    var isConfigured: Bool {
        configuredClientID != nil
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restorePreviousSignIn() {
        guard isConfigured else {
            didRestorePreviousSignIn = true
            setLocalizedError("googleAuth.notConfigured")
            return
        }
        guard !isRestoring else { return }
        isRestoring = true
        didRestorePreviousSignIn = false
        clearError()

        Task { [weak self] in
            await self?.restoreSignInState()
        }
    }

    func signIn() {
        guard isConfigured else {
            setLocalizedError("googleAuth.notConfigured")
            return
        }

        guard let presentingViewController = UIApplication.shared.topMostViewController else {
            setLocalizedError("googleAuth.noPresenter")
            return
        }

        isSigningIn = true
        clearError()

        GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            hint: nil,
            additionalScopes: [contactsScope]
        ) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                self.isSigningIn = false

                if let error {
                    if error.isCanceledGoogleSignIn {
                        // Closing the system authentication browser is an intentional
                        // user action. Return to the sign-in screen without presenting
                        // a failure alert or terminating the app.
                        self.clearError()
                        self.user = nil
                        return
                    }

                    self.setLocalizedError("googleAuth.signInFailed")
                    self.user = nil
                    return
                }

                guard let result else {
                    self.setLocalizedError("googleAuth.emptyResult")
                    self.user = nil
                    return
                }

                guard self.hasRequiredContactsScope(result.user) else {
                    // Google allows the user to continue without selecting an optional
                    // scope. ContactDeck cannot function without contacts access, so
                    // revoke the incomplete grant before retrying. A local sign-out is
                    // insufficient because Google would otherwise remember the partial
                    // authorization on the next consent screen.
                    do {
                        try await GIDSignIn.sharedInstance.disconnect()
                    } catch {
                        GIDSignIn.sharedInstance.signOut()
                    }
                    self.setLocalizedError("googleAuth.contactsPermissionRequired")
                    self.user = nil
                    return
                }

                if let configuredClientID = self.configuredClientID {
                    self.defaults.set(configuredClientID, forKey: self.clientIDMarkerKey)
                }
                self.user = GoogleSignedInUser(user: result.user)
            }
        }
    }

    func signOutAndDisconnect() async {
        guard !isDisconnecting, user != nil else { return }

        isDisconnecting = true
        clearError()

        do {
            try await GIDSignIn.sharedInstance.disconnect()
            self.user = nil
        } catch {
            setRawError(error.localizedDescription)
        }

        isDisconnecting = false
    }

    func clearError() {
        errorMessage = nil
        errorMessageKey = nil
    }

    func freshAccessToken() async throws -> String {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleAuthError.notSignedIn
        }

        return try await withCheckedThrowingContinuation { continuation in
            currentUser.refreshTokensIfNeeded { user, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let token = user?.accessToken.tokenString else {
                    continuation.resume(throwing: GoogleAuthError.missingAccessToken)
                    return
                }

                continuation.resume(returning: token)
            }
        }
    }

    private func setLocalizedError(_ key: String) {
        errorMessageKey = key
        errorMessage = String(localized: String.LocalizationValue(key))
    }

    private func setRawError(_ message: String) {
        errorMessageKey = nil
        errorMessage = message
    }

    private func restoreSignInState() async {
        defer {
            isRestoring = false
            didRestorePreviousSignIn = true
        }

        do {
            clearLegacyContactCache()

            guard let configuredClientID else {
                setLocalizedError("googleAuth.notConfigured")
                user = nil
                return
            }

            if defaults.string(forKey: clientIDMarkerKey) != configuredClientID {
                // Tokens issued for a previous OAuth project cannot be refreshed after
                // that project is replaced or deleted. Clear them locally without
                // calling disconnect, which may itself fail for the deleted project.
                GIDSignIn.sharedInstance.signOut()
                defaults.set(configuredClientID, forKey: clientIDMarkerKey)
                user = nil
                return
            }

            guard GIDSignIn.sharedInstance.hasPreviousSignIn() else {
                user = nil
                return
            }

            let restoredUser = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            guard hasRequiredContactsScope(restoredUser) else {
                GIDSignIn.sharedInstance.signOut()
                setLocalizedError("googleAuth.contactsPermissionRequired")
                user = nil
                return
            }
            user = GoogleSignedInUser(user: restoredUser)
        } catch {
            if error.isNoPreviousGoogleSignIn {
                user = nil
                return
            }

            setRawError(error.localizedDescription)
            user = nil
        }
    }

    private func clearLegacyContactCache() {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("googlePeopleContacts.") }
            .forEach(defaults.removeObject(forKey:))
    }

    private var configuredClientID: String? {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty,
              !clientID.contains("REPLACE_WITH") else {
            return nil
        }
        return clientID
    }

    private func hasRequiredContactsScope(_ user: GIDGoogleUser) -> Bool {
        user.grantedScopes?.contains(contactsScope) == true
    }
}

struct GoogleSignedInUser: Equatable {
    let userID: String?
    let email: String?
    let fullName: String?
    let givenName: String?
    let familyName: String?
    let grantedScopes: [String]

    init(user: GIDGoogleUser) {
        userID = user.userID
        email = user.profile?.email
        fullName = user.profile?.name
        givenName = user.profile?.givenName
        familyName = user.profile?.familyName
        grantedScopes = user.grantedScopes ?? []
    }
}

enum GoogleAuthError: LocalizedError {
    case notSignedIn
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            String(localized: "googleAuth.notSignedIn")
        case .missingAccessToken:
            String(localized: "googleAuth.missingAccessToken")
        }
    }
}

private extension Error {
    var isNoPreviousGoogleSignIn: Bool {
        let nsError = self as NSError
        return nsError.domain == "com.google.GIDSignIn" && nsError.code == -4
    }

    var isCanceledGoogleSignIn: Bool {
        let nsError = self as NSError
        return nsError.domain == "com.google.GIDSignIn" && nsError.code == -5
    }
}

private extension UIApplication {
    var topMostViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topMostPresentedViewController
    }
}

private extension UIViewController {
    var topMostPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostPresentedViewController
        }

        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.topMostPresentedViewController
        }

        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.topMostPresentedViewController
        }

        return self
    }
}
