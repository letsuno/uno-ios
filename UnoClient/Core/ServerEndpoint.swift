import Foundation

/// A normalized server link. The web client stores a bare authority and derives the
/// scheme from the page; a native client defaults to https unless the user is explicit.
struct ServerEndpoint: Equatable, Hashable, Codable, Sendable {
    /// The bundled public server: always one tap away on the landing screen, and for that
    /// reason deliberately kept out of the recent-server history.
    static let `default` = ServerEndpoint(baseURL: URL(string: "https://uno.aunly.cn")!)
    static var defaultAddress: String { Self.default.baseURL.absoluteString }

    let baseURL: URL

    init?(userInput: String) {
        var text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        while text.hasSuffix("/") { text.removeLast() }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme,
            ["http", "https"].contains(scheme), let host = url.host(),
            url.user == nil, url.password == nil, url.fragment == nil
        else { return nil }
        guard scheme == "https" || Self.isLocalHost(host) else { return nil }
        self.baseURL = url
    }

    private init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Keychain / persistence identity for this server.
    var storageKey: String {
        let host = baseURL.host() ?? "unknown"
        let port = baseURL.port.map { ":\($0)" } ?? ""
        return "\(baseURL.scheme ?? "https")://\(host)\(port)"
    }

    var isDefault: Bool { storageKey == Self.default.storageKey }

    var displayName: String {
        let host = baseURL.host() ?? baseURL.absoluteString
        let port = baseURL.port.map { ":\($0)" } ?? ""
        return host + port
    }

    /// A plain-http variant for LAN/dev servers, used as a fallback probe.
    var insecureVariant: ServerEndpoint? {
        guard baseURL.scheme == "https", let host = baseURL.host(), Self.isLocalHost(host),
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        else { return nil }
        components.scheme = "http"
        return components.url.map(ServerEndpoint.init(baseURL:))
    }

    func api(_ path: String) -> URL {
        baseURL.appending(path: "/api" + path)
    }

    /// Avatar URLs arrive either absolute (external) or relative (`/api/avatar/<id>`).
    func resolveAvatar(_ avatarUrl: String?) -> URL? {
        guard let avatarUrl, !avatarUrl.isEmpty else { return nil }
        if avatarUrl.hasPrefix("http://") || avatarUrl.hasPrefix("https://") {
            return URL(string: avatarUrl)
        }
        return URL(string: avatarUrl, relativeTo: baseURL)?.absoluteURL
    }

    private static func isLocalHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".local")
            || (!host.contains(".") && !host.contains(":"))
        {
            return true
        }

        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        if octets.count == 4 {
            return octets[0] == 10
                || octets[0] == 127
                || octets[0] == 169 && octets[1] == 254
                || octets[0] == 172 && (16...31).contains(octets[1])
                || octets[0] == 192 && octets[1] == 168
        }

        if host == "::1" { return true }
        guard let firstHextet = host.split(separator: ":").first,
            let value = UInt16(firstHextet, radix: 16)
        else { return false }
        return value & 0xFE00 == 0xFC00 || value & 0xFFC0 == 0xFE80
    }
}
