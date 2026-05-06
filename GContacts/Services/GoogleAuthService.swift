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
    var errorMessage: String?

    var isConfigured: Bool {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            return false
        }
        return !clientID.isEmpty && !clientID.contains("REPLACE_WITH")
    }

    func restorePreviousSignIn() {
        guard isConfigured else { return }
        isRestoring = true
        errorMessage = nil

        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            Task { @MainActor in
                guard let self else { return }
                self.isRestoring = false

                if let error {
                    if error.isNoPreviousGoogleSignIn {
                        self.user = nil
                        return
                    }

                    self.errorMessage = error.localizedDescription
                    self.user = nil
                    return
                }

                self.user = user.map(GoogleSignedInUser.init)
            }
        }
    }

    func signIn() {
        guard isConfigured else {
            errorMessage = String(localized: "googleAuth.notConfigured")
            return
        }

        guard let presentingViewController = UIApplication.shared.topMostViewController else {
            errorMessage = String(localized: "googleAuth.noPresenter")
            return
        }

        isSigningIn = true
        errorMessage = nil

        GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            hint: nil,
            additionalScopes: [contactsScope]
        ) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                self.isSigningIn = false

                if let error {
                    self.errorMessage = error.localizedDescription
                    self.user = nil
                    return
                }

                guard let result else {
                    self.errorMessage = String(localized: "googleAuth.emptyResult")
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
        errorMessage = nil
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
