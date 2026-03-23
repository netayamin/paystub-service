import Foundation
import SwiftUI

/// Persists phone login + profile locally; access token from `/chat/auth/*` for API calls that need it later.
@MainActor
final class AuthSessionManager: ObservableObject {
    private enum K {
        static let signedIn = "auth.signedIn"
        static let token = "auth.accessToken"
        static let phone = "auth.phoneE164"
        static let first = "auth.firstName"
        static let last = "auth.lastName"
        static let email = "auth.email"
        static let pendingToken = "auth.pendingAccessToken"
        static let pendingPhone = "auth.pendingPhoneE164"
    }

    private let defaults = UserDefaults.standard

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var accessToken: String?
    @Published private(set) var phoneE164: String
    @Published private(set) var firstName: String
    @Published private(set) var lastName: String
    @Published private(set) var email: String

    /// Verified phone but profile not finished (e.g. app closed mid-flow).
    var awaitingProfile: Bool {
        (defaults.string(forKey: K.pendingToken) ?? "").isEmpty == false && !isSignedIn
    }

    init() {
        isSignedIn = defaults.bool(forKey: K.signedIn)
        accessToken = defaults.string(forKey: K.token)
        phoneE164 = defaults.string(forKey: K.phone) ?? ""
        firstName = defaults.string(forKey: K.first) ?? ""
        lastName = defaults.string(forKey: K.last) ?? ""
        email = defaults.string(forKey: K.email) ?? ""
    }

    var displayName: String {
        let f = firstName.trimmingCharacters(in: .whitespaces)
        let l = lastName.trimmingCharacters(in: .whitespaces)
        if !f.isEmpty { return f }
        if !l.isEmpty { return l }
        return "there"
    }

    func setPendingVerification(phone: String, token: String) {
        defaults.set(phone, forKey: K.pendingPhone)
        defaults.set(token, forKey: K.pendingToken)
    }

    func pendingPhoneAndToken() -> (phone: String, token: String)? {
        guard let t = defaults.string(forKey: K.pendingToken), !t.isEmpty,
              let p = defaults.string(forKey: K.pendingPhone), !p.isEmpty else { return nil }
        return (p, t)
    }

    func clearPendingVerification() {
        defaults.removeObject(forKey: K.pendingToken)
        defaults.removeObject(forKey: K.pendingPhone)
    }

    func completeSignIn(phone: String, token: String, first: String, last: String, email: String) {
        let f = first.trimmingCharacters(in: .whitespaces)
        let l = last.trimmingCharacters(in: .whitespaces)
        let em = email.trimmingCharacters(in: .whitespaces)
        defaults.set(true, forKey: K.signedIn)
        defaults.set(token, forKey: K.token)
        defaults.set(phone, forKey: K.phone)
        defaults.set(f, forKey: K.first)
        defaults.set(l, forKey: K.last)
        defaults.set(em, forKey: K.email)
        clearPendingVerification()
        isSignedIn = true
        accessToken = token
        phoneE164 = phone
        firstName = f
        lastName = l
        self.email = em
    }

    func signOut() {
        let keys = [K.signedIn, K.token, K.phone, K.first, K.last, K.email, K.pendingToken, K.pendingPhone]
        for k in keys { defaults.removeObject(forKey: k) }
        isSignedIn = false
        accessToken = nil
        phoneE164 = ""
        firstName = ""
        lastName = ""
        email = ""
    }
}
