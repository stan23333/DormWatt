//
//  StorageServices.swift
//  DormWatt
//

import Foundation
import Security

protocol PasswordStore {
    func loadPassword() throws -> String?
    func savePassword(_ password: String) throws
    func deletePassword() throws
}

final class AppSettingsStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "appSettings") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: key)
    }
}

final class ElectricityHistoryStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = DormWattSharedConfiguration.sharedDefaults(), key: String = "electricityHistoryRecords") {
        self.defaults = defaults
        self.key = key
    }

    func loadRecords() -> [ElectricityRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([ElectricityRecord].self, from: data) else {
            return []
        }
        return ElectricityAnalytics.sorted(records)
    }

    func saveRecord(_ record: ElectricityRecord) throws {
        var records = loadRecords()
        records.removeAll { $0.timestamp == record.timestamp }
        records.append(record)
        try replaceRecords(records)
    }

    func replaceRecords(_ records: [ElectricityRecord]) throws {
        let sortedRecords = ElectricityAnalytics.sorted(records)
        let data = try JSONEncoder().encode(sortedRecords)
        defaults.set(data, forKey: key)
    }

    func clearRecords() {
        defaults.removeObject(forKey: key)
    }

    func latestRecord() -> ElectricityRecord? {
        loadRecords().last
    }
}

final class SharedElectricityStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = DormWattSharedConfiguration.sharedDefaults(), key: String = "latestElectricityRecord") {
        self.defaults = defaults
        self.key = key
    }

    func loadLatestRecord() -> ElectricityRecord? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(ElectricityRecord.self, from: data)
    }

    func saveLatestRecord(_ record: ElectricityRecord) throws {
        let data = try JSONEncoder().encode(record)
        defaults.set(data, forKey: key)
    }

    func clearLatestRecord() {
        defaults.removeObject(forKey: key)
    }
}

final class KeychainService: PasswordStore {
    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.example.DormWatt",
        account: String = "electricityWebsitePassword"
    ) {
        self.service = service
        self.account = account
    }

    func loadPassword() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw keychainError(status)
        }

        guard let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func savePassword(_ password: String) throws {
        let data = Data(password.utf8)
        var query = baseQuery()
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw keychainError(updateStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw keychainError(status)
        }
    }

    func deletePassword() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func keychainError(_ status: OSStatus) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"]
        )
    }
}
