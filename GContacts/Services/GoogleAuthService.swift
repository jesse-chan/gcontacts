import Foundation
import GoogleSignIn
import UIKit

@MainActor
@Observable
final class GoogleAuthService {
    private let contactsScope = "https://www.googleapis.com/auth/contacts"

    private(set) var user: GoogleSignedInUser?
    private(set) var isRestoring = false
    private(set) var isSigningIn = false
    private(set) var didRestorePreviousSignIn = false
    private(set) var errorMessageKey: String?
    var errorMessage: String?

    var isConfigured: Bool {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            return false
        }
        return !clientID.isEmpty && !clientID.contains("REPLACE_WITH")
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

        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            Task { @MainActor in
                guard let self else { return }
                self.isRestoring = false
                self.didRestorePreviousSignIn = true

                if let error {
                    if error.isNoPreviousGoogleSignIn {
                        self.user = nil
                        return
                    }

                    self.setRawError(error.localizedDescription)
                    self.user = nil
                    return
                }

                self.user = user.map(GoogleSignedInUser.init)
            }
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
                    self.setLocalizedError(error.isCanceledGoogleSignIn ? "googleAuth.signInCancelled" : "googleAuth.signInFailed")
                    self.user = nil
                    return
                }

                guard let result else {
                    self.setLocalizedError("googleAuth.emptyResult")
                    self.user = nil
                    return
                }

                self.user = GoogleSignedInUser(user: result.user)
            }
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        user = nil
        clearError()
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
