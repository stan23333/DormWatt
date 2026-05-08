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
        defaults.synchronize()
    }
}

final class ElectricityHistoryStore {
    private let defaults: UserDefaults
    private let fallbackDefaults: UserDefaults?
    private let key: String
    private let fileURL: URL?
    private let usesLegacySharedDefaults: Bool

    init(
        defaults: UserDefaults = DormWattSharedConfiguration.sharedDefaults(),
        fallbackDefaults: UserDefaults? = nil,
        key: String = "electricityHistoryRecords",
        fileURL: URL? = DormWattSharedConfiguration.sharedDataURL(fileName: "electricity-history.json"),
        usesLegacySharedDefaults: Bool = true
    ) {
        self.defaults = defaults
        self.fallbackDefaults = fallbackDefaults
        self.key = key
        self.fileURL = fileURL
        self.usesLegacySharedDefaults = usesLegacySharedDefaults
    }

    func loadRecords() -> [ElectricityRecord] {
        let data = dataFromFile()
            ?? legacySharedDefaultsData()
            ?? defaults.data(forKey: key)
            ?? fallbackDefaults?.data(forKey: key)
        guard let data,
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
        try saveDataToFile(data)
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }

    func clearRecords() {
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        defaults.removeObject(forKey: key)
        defaults.synchronize()
    }

    func latestRecord() -> ElectricityRecord? {
        loadRecords().last
    }

    private func dataFromFile() -> Data? {
        guard let fileURL else {
            return nil
        }
        return try? Data(contentsOf: fileURL)
    }

    private func legacySharedDefaultsData() -> Data? {
        guard usesLegacySharedDefaults else {
            return nil
        }
        return DormWattSharedConfiguration.legacySharedDefaultsData(forKey: key)
    }

    private func saveDataToFile(_ data: Data) throws {
        guard let fileURL else {
            return
        }
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }
}

final class SharedElectricityStore {
    private let defaults: UserDefaults
    private let fallbackDefaults: UserDefaults?
    private let key: String
    private let fileURL: URL?
    private let usesLegacySharedDefaults: Bool

    init(
        defaults: UserDefaults = DormWattSharedConfiguration.sharedDefaults(),
        fallbackDefaults: UserDefaults? = nil,
        key: String = "latestElectricityRecord",
        fileURL: URL? = DormWattSharedConfiguration.sharedDataURL(fileName: "latest-electricity-record.json"),
        usesLegacySharedDefaults: Bool = true
    ) {
        self.defaults = defaults
        self.fallbackDefaults = fallbackDefaults
        self.key = key
        self.fileURL = fileURL
        self.usesLegacySharedDefaults = usesLegacySharedDefaults
    }

    func loadLatestRecord() -> ElectricityRecord? {
        guard let data = dataFromFile()
            ?? legacySharedDefaultsData()
            ?? defaults.data(forKey: key)
            ?? fallbackDefaults?.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(ElectricityRecord.self, from: data)
    }

    func saveLatestRecord(_ record: ElectricityRecord) throws {
        let data = try JSONEncoder().encode(record)
        try saveDataToFile(data)
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }

    func clearLatestRecord() {
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        defaults.removeObject(forKey: key)
        defaults.synchronize()
    }

    private func dataFromFile() -> Data? {
        guard let fileURL else {
            return nil
        }
        return try? Data(contentsOf: fileURL)
    }

    private func legacySharedDefaultsData() -> Data? {
        guard usesLegacySharedDefaults else {
            return nil
        }
        return DormWattSharedConfiguration.legacySharedDefaultsData(forKey: key)
    }

    private func saveDataToFile(_ data: Data) throws {
        guard let fileURL else {
            return
        }
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }
}

final class KeychainService: PasswordStore {
    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "mercury.DormWatt",
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
