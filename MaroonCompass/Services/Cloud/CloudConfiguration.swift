import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Public Supabase project settings. The app only ever holds a publishable (anon) key; a
/// service-role or secret key is rejected so it cannot ship by mistake.
///
/// Settings come from an uncommitted `SupabaseConfig.plist` in the app bundle
/// (see `Configuration/SupabaseConfig.example.plist`). Without it the app runs in local mode.
struct SupabaseConfiguration: Sendable, Equatable {
    let projectURL: URL
    let publishableKey: String
    /// Anonymous, non-restorable development sessions. Honored only in Debug builds.
    let allowsDevelopmentSessions: Bool
    /// Enable only after the Sign in with Apple capability is provisioned for this bundle ID.
    let signInWithAppleEnabled: Bool

    static let resourceName = "SupabaseConfig"

    init?(
        projectURL: URL,
        publishableKey: String,
        allowsDevelopmentSessions: Bool = false,
        signInWithAppleEnabled: Bool = false
    ) {
        let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isAcceptableProjectURL(projectURL), Self.isPublishableKey(key) else { return nil }
        self.projectURL = projectURL
        self.publishableKey = key
        #if DEBUG
        self.allowsDevelopmentSessions = allowsDevelopmentSessions
        #else
        self.allowsDevelopmentSessions = false
        #endif
        self.signInWithAppleEnabled = signInWithAppleEnabled
    }

    static func fromBundle(_ bundle: Bundle = .main) -> Self? {
        if let url = bundle.url(forResource: resourceName, withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            return from(values)
        }
        // Earlier builds documented these Info.plist keys; keep reading them.
        guard let rawURL = bundle.object(forInfoDictionaryKey: "MCSupabaseURL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "MCSupabasePublishableKey") as? String else { return nil }
        return from(["ProjectURL": rawURL, "PublishableKey": key])
    }

    static func from(_ values: [String: Any]) -> Self? {
        guard let rawURL = values["ProjectURL"] as? String,
              let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = values["PublishableKey"] as? String else { return nil }
        return Self(
            projectURL: url,
            publishableKey: key,
            allowsDevelopmentSessions: values["AllowDevelopmentSessions"] as? Bool ?? false,
            signInWithAppleEnabled: values["SignInWithAppleEnabled"] as? Bool ?? false
        )
    }

    /// HTTPS only. Debug builds may also reach a Supabase CLI stack on this machine.
    static func isAcceptableProjectURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
        if scheme == "https" { return true }
        #if DEBUG
        return scheme == "http" && (host == "127.0.0.1" || host == "localhost")
        #else
        return false
        #endif
    }

    /// Accepts `sb_publishable_…` keys and legacy JWT keys whose role is `anon`.
    static func isPublishableKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.count <= 2_048, !key.contains(where: \.isWhitespace) else { return false }
        if key.hasPrefix("sb_publishable_") { return true }
        if key.hasPrefix("sb_secret_") { return false }
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let payload = Data(base64URLEncoded: String(parts[1])),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return false }
        return claims["role"] as? String == "anon"
    }

    func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: projectURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = base + "/" + path
        components.queryItems = query.isEmpty ? nil : query
        // Force-unwrapping is safe: the base URL was validated and the path is a constant.
        return components.url!
    }
}

/// The only network boundary used by cloud code, so tests can substitute responses.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// An ephemeral session: no URL cache, cookies, or credential storage, so tokens and schedule
/// payloads are never written to disk by the networking stack.
final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

extension URLRequest {
    static func supabase(
        _ url: URL,
        method: String,
        configuration: SupabaseConfiguration,
        accessToken: String? = nil,
        json body: (any Encodable)? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }
}

extension Error {
    /// Connectivity failures that should leave local state untouched and allow a retry.
    var isConnectivityFailure: Bool {
        guard let error = self as? URLError else { return false }
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
             .callIsActive, .secureConnectionFailed, .cannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }
}

extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}

/// Canonical text forms shared by the cloud snapshot and its validation.
enum CloudFormat {
    private static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!

    private static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    /// `yyyy-MM-dd` for a real calendar date.
    static func isValidDate(_ text: String) -> Bool {
        guard text.count == 10, text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = gregorianUTC.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return false }
        let check = gregorianUTC.dateComponents([.year, .month, .day], from: date)
        return check.year == parts[0] && check.month == parts[1] && check.day == parts[2]
    }

    static func clock(hour: Int, minute: Int) -> String? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    /// Parses the strict `HH:mm` form the server returns.
    static func parseClock(_ text: String) -> (hour: Int, minute: Int)? {
        guard text.count == 5, text.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    /// UTC timestamp with millisecond precision, matching the server's output exactly.
    static func timestamp(_ date: Date) -> String {
        let milliseconds = Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
        let seconds = milliseconds >= 0 ? milliseconds / 1_000 : (milliseconds - 999) / 1_000
        let fraction = milliseconds - seconds * 1_000
        let components = gregorianUTC.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: TimeInterval(seconds))
        )
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            components.year ?? 0, components.month ?? 0, components.day ?? 0,
            components.hour ?? 0, components.minute ?? 0, components.second ?? 0, Int(fraction)
        )
    }

    static func parseTimestamp(_ text: String) -> Date? {
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3})Z$"#
        guard text.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let digits = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard digits.count == 7,
              let date = gregorianUTC.date(from: DateComponents(
                  year: digits[0], month: digits[1], day: digits[2],
                  hour: digits[3], minute: digits[4], second: digits[5]
              )) else { return nil }
        return date.addingTimeInterval(TimeInterval(digits[6]) / 1_000)
    }
}
