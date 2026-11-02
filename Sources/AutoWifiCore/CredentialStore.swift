import Foundation
import OSLog
import Security

public enum CredentialAccount {
    public static let priority = "passwordP"
    public static let backup = "passwordB"
}

public enum CredentialStoreError: Error, Equatable, Sendable {
    case keychain(OSStatus)
    case invalidData
    case verificationFailed
}

/// Abstraction over password persistence so tests (and alternate builds) can
/// avoid touching the user's real keychain.
public protocol CredentialStore: Sendable {
    func password(for account: String) throws -> String?
    func setPassword(_ password: String, for account: String) throws
    func removePassword(for account: String) throws
}

/// Stores Wi-Fi passwords as generic-password items in the user's keychain.
/// Writing an empty password removes the item.
public final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    public static let shared = KeychainCredentialStore()

    private static let logger = Logger(subsystem: "com.linmu.AutoWifi", category: "credential")
    private let service: String

    public init(service: String = "com.linmu.AutoWifi") {
        self.service = service
    }

    public func password(for account: String) throws -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            Self.logger.error("Keychain read failed with status \(status)")
            throw CredentialStoreError.keychain(status)
        }
        guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            Self.logger.error("Keychain returned non-UTF8 password data")
            throw CredentialStoreError.invalidData
        }
        return password
    }

    public func setPassword(_ password: String, for account: String) throws {
        guard !password.isEmpty else {
            try removePassword(for: account)
            return
        }

        let data = Data(password.utf8)
        let query = baseQuery(for: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            Self.logger.error("Keychain update failed with status \(updateStatus)")
            throw CredentialStoreError.keychain(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            Self.logger.error("Keychain add failed with status \(addStatus)")
            throw CredentialStoreError.keychain(addStatus)
        }
    }

    public func removePassword(for account: String) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Self.logger.error("Keychain delete failed with status \(status)")
            throw CredentialStoreError.keychain(status)
        }
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
