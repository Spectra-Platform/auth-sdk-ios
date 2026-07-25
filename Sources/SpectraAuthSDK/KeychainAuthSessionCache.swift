import Foundation

#if canImport(Security)
import Security

public struct KeychainAuthSessionCache: AuthSessionCache {
    public let service: String
    public let account: String
    public let accessGroup: String?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        service: String = "kr.spectra.auth-sdk.session",
        account: String,
        accessGroup: String? = nil
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func loadSession() async throws -> AuthSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw keychainError(operation: .load, status: status)
        }
        guard let data = item as? Data else {
            throw AuthError.sessionCacheFailed(operation: .load, reason: "Stored Keychain item was not data.")
        }
        do {
            return try decoder.decode(AuthSession.self, from: data)
        } catch {
            throw AuthError.sessionCacheFailed(operation: .load, reason: "Stored session could not be decoded.")
        }
    }

    public func storeSession(_ session: AuthSession) async throws {
        let data: Data
        do {
            data = try encoder.encode(session)
        } catch {
            throw AuthError.sessionCacheFailed(operation: .store, reason: "Session could not be encoded.")
        }

        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw keychainError(operation: .store, status: updateStatus)
        }

        var addQuery = query
        attributes.forEach { key, value in
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw keychainError(operation: .store, status: addStatus)
        }
    }

    public func clearSession() async throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(operation: .clear, status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func keychainError(operation: AuthSessionCacheOperation, status: OSStatus) -> AuthError {
        AuthError.sessionCacheFailed(operation: operation, reason: "Keychain OSStatus \(status).")
    }
}
#else
public struct KeychainAuthSessionCache: AuthSessionCache {
    public init(
        service: String = "kr.spectra.auth-sdk.session",
        account: String,
        accessGroup: String? = nil
    ) {}

    public func loadSession() async throws -> AuthSession? {
        throw AuthError.sessionCacheUnavailable
    }

    public func storeSession(_ session: AuthSession) async throws {
        throw AuthError.sessionCacheUnavailable
    }

    public func clearSession() async throws {
        throw AuthError.sessionCacheUnavailable
    }
}
#endif
