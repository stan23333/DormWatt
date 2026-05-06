//
//  ElectricityRefreshManager.swift
//  DormWatt
//

import Foundation

protocol ElectricityCollector {
    @MainActor
    func collectBalance(
        settings: AppSettings,
        password: String,
        stateDidChange: ((CollectorState) -> Void)?,
        logDidAppend: ((String) -> Void)?
    ) async throws -> ElectricityRecord
}

extension ElectricityCollector {
    @MainActor
    func collectBalance(settings: AppSettings, password: String) async throws -> ElectricityRecord {
        try await collectBalance(settings: settings, password: password, stateDidChange: nil, logDidAppend: nil)
    }
}

final class ElectricityRefreshManager {
    private let settingsStore: AppSettingsStore
    private let keychainService: PasswordStore
    private let recordStore: SharedElectricityStore
    private let collector: ElectricityCollector

    init(
        settingsStore: AppSettingsStore,
        keychainService: PasswordStore,
        recordStore: SharedElectricityStore,
        collector: ElectricityCollector
    ) {
        self.settingsStore = settingsStore
        self.keychainService = keychainService
        self.recordStore = recordStore
        self.collector = collector
    }

    @MainActor
    convenience init() {
        self.init(
            settingsStore: AppSettingsStore(),
            keychainService: KeychainService(),
            recordStore: SharedElectricityStore(),
            collector: WKWebViewElectricityCollector()
        )
    }

    func latestRecord() -> ElectricityRecord? {
        recordStore.loadLatestRecord()
    }

    @MainActor
    func refresh(
        stateDidChange: ((CollectorState) -> Void)? = nil,
        logDidAppend: ((String) -> Void)? = nil
    ) async throws -> ElectricityRecord {
        let settings = settingsStore.load()
        logDidAppend?("Loaded settings. loginURL=\(settings.loginURL), balanceSelector=\(settings.balanceTextSelector)")
        guard let password = try keychainService.loadPassword(), !password.isEmpty else {
            logDidAppend?("Password missing in Keychain.")
            throw DormWattError.missingPassword
        }

        let record = try await collector.collectBalance(
            settings: settings,
            password: password,
            stateDidChange: stateDidChange,
            logDidAppend: logDidAppend
        )
        try recordStore.saveLatestRecord(record)
        logDidAppend?("Saved latest record. balance=\(record.balance)")
        return record
    }
}
