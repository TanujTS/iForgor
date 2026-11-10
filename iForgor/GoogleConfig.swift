import Foundation

enum GoogleConfig {
    /// iOS-type OAuth client ID from Google Cloud Console, e.g. "1234-abc.apps.googleusercontent.com".
    /// Client IDs of native apps ship inside the app and are not secrets.
    static let clientID = "382037776207-0p3rg6iprp8blp10cprsaauoe6qvdli5.apps.googleusercontent.com"

    static let scopes = ["openid", "email", "https://www.googleapis.com/auth/tasks"]

    static var isConfigured: Bool { clientID.hasSuffix(".apps.googleusercontent.com") }

    /// Google's redirect scheme for native clients is the client ID with its dot-separated parts reversed.
    static var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    static var redirectURI: String { "\(redirectScheme):/oauth2redirect" }
}
