import Foundation
import Security

public protocol SecureStoreProtocol {
    func string(forKey key: String) throws -> String?
    func setString(_ value: String, forKey key: String) throws
    func removeValue(forKey key: String) throws
}

public enum SecureStoreError: LocalizedError {
    case invalidData
    case osStatus(OSStatus, operation: String)

    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Secure store returned unreadable data."
        case let .osStatus(status, operation):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            return "Secure store \(operation) failed: \(message)"
        }
    }
}

public final class KeychainStore: SecureStoreProtocol, @unchecked Sendable {
    public static let shared = KeychainStore(
        service: Bundle.main.bundleIdentifier ?? "com.linmu.AutoWifi"
    )

    private let service: String

    public init(service: String) {
        self.service = service
    }

    public func string(forKey key: String) throws -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard
                let data = item as? Data,
                let value = String(data: data, encoding: .utf8)
            else {
                throw SecureStoreError.invalidData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw SecureStoreError.osStatus(status, operation: "read")
        }
    }

    public func setString(_ value: String, forKey key: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(forKey: key)
        let attributesToUpdate = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributesToUpdate as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var itemToAdd = query
            itemToAdd[kSecValueData as String] = data
            let addStatus = SecItemAdd(itemToAdd as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecureStoreError.osStatus(addStatus, operation: "write")
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw SecureStoreError.osStatus(updateStatus, operation: "write")
        }
    }

    public func removeValue(forKey key: String) throws {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.osStatus(status, operation: "delete")
        }
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
