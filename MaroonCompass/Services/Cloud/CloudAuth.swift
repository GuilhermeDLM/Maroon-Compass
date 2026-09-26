import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// The signed-in identity. Deliberately excludes email and name: the app never needs them.
struct AuthUser: Codable, Equatable, Hashable, Sendable {
    let id: UUID
    /// Supabase anonymous user. Only created by Debug development sessions; never restorable.
    let isAnonymous: Bool
    let provider: String?
}

/// A Supabase Auth session. Stored only in the Keychain; its tokens are redacted from every
/// textual and reflected representation so they cannot reach logs.
struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    func needsRefresh(at now: Date, leeway: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) <= leeway
    }
}

extension AuthSession: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var description: String {
        "AuthSession(user: \(user.id.uuidString), anonymous: \(user.isAnonymous), expiresAt: \(expiresAt), tokens: <redacted>)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror {
        Mirror(self, children: ["user": user, "expiresAt": expiresAt, "tokens": "<redacted>"], displayStyle: .struct)
    }
}

/// Persistent session storage. The app uses the Keychain; tests use memory.
protocol AuthSessionStore: Sendable {
    func load() throws -> AuthSession?
    func save(_ session: AuthSession) throws
    func clear() throws
}

final class InMemoryAuthSessionStore: AuthSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?

    init(_ session: AuthSession? = nil) { self.session = session }

    func load() throws -> AuthSession? { lock.withLock { session } }
    func save(_ session: AuthSession) throws { lock.withLock { self.session = session } }
    func clear() throws { lock.withLock { session = nil } }
}

enum CloudAuthError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case signedOut
    case offline
    case signInRejected
    case signInCancelled
    case sessionExpired
    case developmentSessionsUnavailable
    case rateLimited
    case storageFailed
    case server(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Cloud backup isn't set up in this build. Your schedule works fully on this device."
        case .signedOut: "Sign in to use cloud backup."
        case .offline: "You're offline. Nothing changed; try again when you're connected."
        case .signInRejected: "Sign-in was not accepted. Nothing changed on this device."
        case .signInCancelled: "Sign-in was cancelled. Nothing changed on this device."
        case .sessionExpired: "Your cloud session ended. Sign in again; your schedule on this device is unchanged."
        case .developmentSessionsUnavailable: "Development sessions are only available in Debug builds."
        case .rateLimited: "Too many attempts. Wait a minute and try again."
        case .storageFailed: "The session couldn't be saved securely on this device."
        case .server: "The account service is unavailable. Your schedule on this device is unchanged."
        case .invalidResponse: "The account service sent an unexpected response."
        }
    }
}

/// One Google sign-in attempt. The PKCE verifier exists only in memory for this attempt and is
/// never stored or logged.
struct OAuthSignInRequest: Sendable, Equatable {
    static let callbackScheme = "marooncompass"
    static let redirectURL = URL(string: "marooncompass://auth/callback")!
    /// Identity only. No Gmail, Google Calendar, or other Google API access is requested.
    static let googleScopes = "openid email profile"

    let authorizeURL: URL
    let codeVerifier: String
}

/// Proof Key for Code Exchange (RFC 7636, S256).
enum PKCE {
    /// 64 characters from the unreserved set, from 48 bytes of system randomness.
    static func makeVerifier() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<48).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(sha256(Data(verifier.utf8)))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func sha256(_ data: Data) -> Data {
        #if canImport(CryptoKit)
        Data(SHA256.hash(data: data))
        #else
        PortableSHA256.hash(data)
        #endif
    }
}

/// Supabase Auth (GoTrue) and the account-deletion Edge Function over plain HTTPS.
struct SupabaseAuthClient: Sendable {
    let configuration: SupabaseConfiguration
    let transport: any HTTPTransport
    var now: @Sendable () -> Date = { Date() }

    static let deletionConfirmation = "delete-my-account"

    /// Starts Google sign-in. The returned URL is opened in a system web-authentication session;
    /// Supabase Auth sends the browser to Google and back to `marooncompass://auth/callback`
    /// with a one-time code bound to this request's PKCE challenge.
    func makeGoogleSignInRequest() -> OAuthSignInRequest {
        let verifier = PKCE.makeVerifier()
        let url = configuration.endpoint("auth/v1/authorize", query: [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: OAuthSignInRequest.redirectURL.absoluteString),
            URLQueryItem(name: "scopes", value: OAuthSignInRequest.googleScopes),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "s256")
        ])
        return OAuthSignInRequest(authorizeURL: url, codeVerifier: verifier)
    }

    /// Exchanges the callback's one-time code and this attempt's verifier for a session.
    func completeOAuthSignIn(callbackURL: URL, request: OAuthSignInRequest) async throws -> AuthSession {
        let code = try Self.authorizationCode(from: callbackURL)
        return try await tokenGrant("pkce", body: ["auth_code": code, "code_verifier": request.codeVerifier])
    }

    /// Reads the one-time code from `marooncompass://auth/callback?code=…`, or the error Supabase
    /// Auth reports in the query or fragment.
    static func authorizationCode(from url: URL) throws -> String {
        guard url.scheme?.lowercased() == OAuthSignInRequest.callbackScheme,
              url.host?.lowercased() == "auth", url.path == "/callback",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw CloudAuthError.invalidResponse
        }
        var items = components.queryItems ?? []
        if let fragment = components.fragment {
            var fragmentComponents = URLComponents()
            fragmentComponents.query = fragment
            items += fragmentComponents.queryItems ?? []
        }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw error == "access_denied" ? CloudAuthError.signInCancelled : CloudAuthError.signInRejected
        }
        guard let code = value("code"), !code.isEmpty, code.count <= 512 else { throw CloudAuthError.invalidResponse }
        return code
    }

    /// Anonymous Supabase user for Debug development sessions only.
    func signInAnonymously() async throws -> AuthSession {
        let request = try URLRequest.supabase(
            configuration.endpoint("auth/v1/signup"), method: "POST",
            configuration: configuration, json: [String: String]()
        )
        return try await session(from: request, rejection: .signInRejected)
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        try await tokenGrant("refresh_token", body: ["refresh_token": refreshToken], rejection: .sessionExpired)
    }

    /// Revokes this device's refresh token. An already-invalid session counts as signed out.
    func signOut(accessToken: String) async throws {
        let request = try URLRequest.supabase(
            configuration.endpoint("auth/v1/logout", query: [URLQueryItem(name: "scope", value: "local")]),
            method: "POST", configuration: configuration, accessToken: accessToken
        )
        let response = try await send(request).1
        switch response.statusCode {
        case 200...299, 401, 403, 404: return
        case 429: throw CloudAuthError.rateLimited
        default: throw CloudAuthError.server(response.statusCode)
        }
    }

    /// Deletes the Auth user through the `delete-account` Edge Function. Schedule rows cascade.
    func deleteAccount(accessToken: String) async throws {
        let request = try URLRequest.supabase(
            configuration.endpoint("functions/v1/delete-account"), method: "POST",
            configuration: configuration, accessToken: accessToken,
            json: ["confirmation": Self.deletionConfirmation]
        )
        let response = try await send(request).1
        switch response.statusCode {
        case 200...299: return
        case 401, 403: throw CloudAuthError.sessionExpired
        case 429: throw CloudAuthError.rateLimited
        default: throw CloudAuthError.server(response.statusCode)
        }
    }

    private func tokenGrant(
        _ grantType: String,
        body: [String: String],
        rejection: CloudAuthError = .signInRejected
    ) async throws -> AuthSession {
        let request = try URLRequest.supabase(
            configuration.endpoint("auth/v1/token", query: [URLQueryItem(name: "grant_type", value: grantType)]),
            method: "POST", configuration: configuration, json: body
        )
        return try await session(from: request, rejection: rejection)
    }

    private func session(from request: URLRequest, rejection: CloudAuthError) async throws -> AuthSession {
        let (data, response) = try await send(request)
        switch response.statusCode {
        case 200...299:
            break
        case 429:
            throw CloudAuthError.rateLimited
        case 400...499:
            throw rejection
        default:
            throw CloudAuthError.server(response.statusCode)
        }
        guard let payload = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !payload.accessToken.isEmpty, !payload.refreshToken.isEmpty else {
            throw CloudAuthError.invalidResponse
        }
        let expiresAt: Date
        if let absolute = payload.expiresAt {
            expiresAt = Date(timeIntervalSince1970: absolute)
        } else if let relative = payload.expiresIn {
            expiresAt = now().addingTimeInterval(relative)
        } else {
            throw CloudAuthError.invalidResponse
        }
        return AuthSession(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiresAt: expiresAt,
            user: AuthUser(
                id: payload.user.id,
                isAnonymous: payload.user.isAnonymous ?? false,
                provider: payload.user.appMetadata?.provider
            )
        )
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch {
            if error.isConnectivityFailure { throw CloudAuthError.offline }
            throw CloudAuthError.server(0)
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: TimeInterval?
        let expiresAt: TimeInterval?
        let user: User

        struct User: Decodable {
            let id: UUID
            let isAnonymous: Bool?
            let appMetadata: AppMetadata?

            struct AppMetadata: Decodable {
                let provider: String?
            }

            enum CodingKeys: String, CodingKey {
                case id
                case isAnonymous = "is_anonymous"
                case appMetadata = "app_metadata"
            }
        }

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case expiresAt = "expires_at"
            case user
        }
    }
}

#if !canImport(CryptoKit)
/// FIPS 180-4 SHA-256 for platforms without CryptoKit (the Linux test harness). Apple platforms
/// use CryptoKit. Both are checked against the RFC 7636 and NIST test vectors.
enum PortableSHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func hash(_ data: Data) -> Data {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift))) }

        func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 { (value >> count) | (value << (32 - count)) }
        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                w[i] = (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(message[chunk + i * 4 + $1]) }
            }
            for i in 16..<64 {
                let s0 = rotate(w[i - 15], 7) ^ rotate(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotate(w[i - 2], 17) ^ rotate(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for i in 0..<64 {
                let s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
                let choice = (e & f) ^ (~e & g)
                let temp1 = hh &+ s1 &+ choice &+ k[i] &+ w[i]
                let s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ majority
                (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ temp1, c, b, a, temp1 &+ temp2)
            }
            h = [h[0] &+ a, h[1] &+ b, h[2] &+ c, h[3] &+ d, h[4] &+ e, h[5] &+ f, h[6] &+ g, h[7] &+ hh]
        }
        return Data(h.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> UInt32(24 - $0 * 8)) } })
    }
}
#endif
