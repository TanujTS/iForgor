import AppKit
import CryptoKit
import Foundation
import Observation

/// Owns the Google sign-in: OAuth with PKCE, the refresh token in the Keychain, and short-lived access tokens in memory.
@MainActor
@Observable
final class GoogleAccount {
    enum Status: Equatable {
        case checking
        case signedOut
        case signingIn
        case signedIn(email: String)
    }

    private(set) var status: Status = .checking
    /// Number of task lists Google returned on the last connection check; proves the token works.
    private(set) var taskListCount: Int?
    private(set) var isCheckingConnection = false
    var message: String?

    @ObservationIgnored private var refreshToken: String?
    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessTokenExpiry = Date.distantPast
    @ObservationIgnored private var pendingSignIn: PendingSignIn?
    private let credentialKey = "credential"

    var email: String? {
        if case .signedIn(let email) = status { email } else { nil }
    }

    /// Restores a saved sign-in at launch, then verifies it with Google.
    func restore() async {
        do {
            guard let data = try Keychain.read(credentialKey) else {
                status = .signedOut
                return
            }
            let saved = try JSONDecoder().decode(SavedCredential.self, from: data)
            refreshToken = saved.refreshToken
            status = .signedIn(email: saved.email)
            await checkConnection()
        } catch {
            status = .signedOut
            message = "Saved Google sign-in could not be read. Sign in again. \(error.localizedDescription)"
        }
    }

    /// Opens Google's sign-in page in the default browser. Google redirects back to our URL scheme,
    /// which arrives in `handleRedirect(_:)`.
    func signIn() {
        guard GoogleConfig.isConfigured else {
            message = "Add your OAuth client ID in GoogleConfig.swift."
            return
        }
        let request = PendingSignIn(verifier: Self.randomURLSafeString(), state: Self.randomURLSafeString())
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: request.verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: request.state),
        ]
        guard NSWorkspace.shared.open(components.url!) else {
            message = "Could not open your default browser."
            return
        }
        pendingSignIn = request
        status = .signingIn
        message = nil
    }

    /// Abandons a browser sign-in; a redirect arriving later is ignored.
    func cancelSignIn() {
        guard pendingSignIn != nil else { return }
        pendingSignIn = nil
        status = .signedOut
        message = "Sign-in was canceled."
    }

    /// Completes sign-in from Google's redirect: checks state, exchanges the code, saves the refresh token.
    func handleRedirect(_ url: URL) async {
        guard url.scheme?.lowercased() == GoogleConfig.redirectScheme.lowercased() else { return }
        guard let request = pendingSignIn else {
            message = "Ignored a Google sign-in response because no sign-in was in progress."
            return
        }
        pendingSignIn = nil
        do {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            if value("error") == "access_denied" {
                status = .signedOut
                message = "Sign-in was canceled."
                return
            }
            if let error = value("error") { throw GoogleError.oauth(error) }
            guard value("state") == request.state, let code = value("code") else { throw GoogleError.invalidCallback }

            let tokens = try await requestTokens([
                "client_id": GoogleConfig.clientID,
                "code": code,
                "code_verifier": request.verifier,
                "grant_type": "authorization_code",
                "redirect_uri": GoogleConfig.redirectURI,
            ])
            guard let newRefreshToken = tokens.refreshToken else { throw GoogleError.missingRefreshToken }
            let email = tokens.idToken.flatMap(Self.email(fromIDToken:)) ?? "Google account"
            try Keychain.save(JSONEncoder().encode(SavedCredential(refreshToken: newRefreshToken, email: email)),
                              for: credentialKey)
            refreshToken = newRefreshToken
            keep(tokens)
            status = .signedIn(email: email)
            await checkConnection()
        } catch {
            status = .signedOut
            message = "Sign-in failed. \(error.localizedDescription)"
        }
    }

    /// Fetches the user's task lists to confirm the saved sign-in still grants Tasks access.
    func checkConnection() async {
        guard !isCheckingConnection else { return }
        isCheckingConnection = true
        defer { isCheckingConnection = false }
        do {
            let token = try await validAccessToken()
            var request = URLRequest(url: URL(string: "https://tasks.googleapis.com/tasks/v1/users/@me/lists?maxResults=100")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.check(response, data)
            taskListCount = try JSONDecoder().decode(TaskListsPage.self, from: data).items?.count ?? 0
            message = nil
        } catch GoogleError.oauth("invalid_grant") {
            // Revoked, or expired (refresh tokens last 7 days while the consent screen is in Testing).
            clearCredentials()
            message = "Your Google sign-in expired or was revoked. Sign in again."
        } catch {
            message = "Could not reach Google Tasks. \(error.localizedDescription)"
        }
    }

    /// Removes the saved sign-in from this Mac, then asks Google to revoke the token.
    func signOut() async {
        let token = refreshToken
        do {
            try Keychain.delete(credentialKey)
        } catch {
            message = "Could not remove the saved sign-in. \(error.localizedDescription)"
            return
        }
        clearCredentials()
        message = nil
        guard let token else { return }
        do {
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formEncoded(["token": token])
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.check(response, data)
        } catch {
            message = "Signed out on this Mac, but Google could not revoke access. You can remove iForgor at myaccount.google.com/permissions."
        }
    }

    /// Returns a cached access token, refreshing it when it is missing or about to expire.
    func validAccessToken() async throws -> String {
        if let accessToken, accessTokenExpiry > Date().addingTimeInterval(60) { return accessToken }
        guard let refreshToken else { throw GoogleError.notSignedIn }
        let tokens = try await requestTokens([
            "client_id": GoogleConfig.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        keep(tokens)
        return tokens.accessToken
    }

    private func keep(_ tokens: TokenResponse) {
        accessToken = tokens.accessToken
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
    }

    private func clearCredentials() {
        try? Keychain.delete(credentialKey)
        refreshToken = nil
        accessToken = nil
        accessTokenExpiry = .distantPast
        taskListCount = nil
        status = .signedOut
    }

    private func requestTokens(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TokenResponse.self, from: data)
    }

    /// Converts non-2xx responses into errors. OAuth endpoints return `{"error": "code"}`;
    /// API endpoints return `{"error": {"message": ...}}`.
    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GoogleError.badResponse }
        guard !(200..<300).contains(http.statusCode) else { return }
        if let body = try? JSONDecoder().decode(OAuthErrorBody.self, from: data) {
            throw GoogleError.oauth(body.error)
        }
        if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
            throw GoogleError.api(status: http.statusCode, message: body.error.message)
        }
        throw GoogleError.api(status: http.statusCode, message: nil)
    }

    private static func formEncoded(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }

    private static func randomURLSafeString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }

    /// Reads the email claim for display. The token came straight from Google over TLS, so it is not re-verified.
    private static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONDecoder().decode(IDTokenClaims.self, from: data))?.email
    }
}

enum GoogleError: LocalizedError, Equatable {
    case oauth(String)
    case api(status: Int, message: String?)
    case invalidCallback
    case missingRefreshToken
    case notSignedIn
    case badResponse

    var errorDescription: String? {
        switch self {
        case .oauth(let code): "Google returned \(code)."
        case .api(let status, let message): "Google returned HTTP \(status)\(message.map { ": \($0)" } ?? ".")"
        case .invalidCallback: "Google's response did not match this sign-in request."
        case .missingRefreshToken: "Google did not return a refresh token."
        case .notSignedIn: "Not signed in."
        case .badResponse: "Unexpected response from Google."
        }
    }
}

/// PKCE verifier and CSRF state for the sign-in currently open in the browser.
private struct PendingSignIn {
    let verifier: String
    let state: String
}

private struct SavedCredential: Codable {
    let refreshToken: String
    let email: String
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let idToken: String?
}

private struct OAuthErrorBody: Decodable {
    let error: String
}

private struct APIErrorBody: Decodable {
    struct Detail: Decodable { let message: String? }
    let error: Detail
}

private struct IDTokenClaims: Decodable {
    let email: String?
}

private struct TaskListsPage: Decodable {
    struct Item: Decodable { let id: String }
    let items: [Item]?
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
