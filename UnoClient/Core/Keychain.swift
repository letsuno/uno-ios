import Foundation
import Security

/// Tokens are stored per server host so switching servers keeps each login.
enum Keychain {
    private static var service: String {
        "\(Bundle.main.bundleIdentifier ?? "UnoClient").token"
    }

    static func token(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setToken(_ token: String?, for account: String) {
        guard let token else {
            SecItemDelete(baseQuery(account: account) as CFDictionary)
            return
        }
        let data = Data(token.utf8)
        var query = baseQuery(account: account)
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
