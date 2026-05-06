//
//  SettingsViewModel.swift
//  DormWatt
//

import Foundation
import ServiceManagement
import WidgetKit

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var loginURL = ""
    @Published var balancePageURL = ""
    @Published var username = ""
    @Published var password = ""
    @Published var usernameSelector = ""
    @Published var passwordSelector = ""
    @Published var loginButtonSelector = ""
    @Published var balanceTextSelector = ""
    @Published var refreshIntervalMinutes = 15
    @Published var lowBalanceThreshold = 5.0
    @Published var backgroundRefreshEnabled = true
    @Published var launchAtLoginEnabled = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusMessageIsError = false

    private let settingsStore: AppSettingsStore
    private let keychainService: PasswordStore
    private let historyStore: ElectricityHistoryStore
    private let sharedElectricityStore: SharedElectricityStore

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        keychainService: PasswordStore = KeychainService(),
        historyStore: ElectricityHistoryStore = ElectricityHistoryStore(),
        sharedElectricityStore: SharedElectricityStore = SharedElectricityStore()
    ) {
        self.settingsStore = settingsStore
        self.keychainService = keychainService
        self.historyStore = historyStore
        self.sharedElectricityStore = sharedElectricityStore
        load()
    }

    var settings: AppSettings {
        AppSettings(
            loginURL: loginURL,
            balancePageURL: balancePageURL,
            username: username,
            usernameSelector: usernameSelector,
            passwordSelector: passwordSelector,
            loginButtonSelector: loginButtonSelector,
            balanceTextSelector: balanceTextSelector,
            refreshIntervalMinutes: refreshIntervalMinutes,
            lowBalanceThreshold: lowBalanceThreshold,
            backgroundRefreshEnabled: backgroundRefreshEnabled,
            launchAtLoginEnabled: launchAtLoginEnabled
        )
    }

    func load() {
        let settings = settingsStore.load()
        loginURL = settings.loginURL
        balancePageURL = settings.balancePageURL
        username = settings.username
        usernameSelector = settings.usernameSelector
        passwordSelector = settings.passwordSelector
        loginButtonSelector = settings.loginButtonSelector
        balanceTextSelector = settings.balanceTextSelector
        refreshIntervalMinutes = settings.refreshIntervalMinutes
        lowBalanceThreshold = settings.lowBalanceThreshold
        backgroundRefreshEnabled = settings.backgroundRefreshEnabled
        launchAtLoginEnabled = settings.launchAtLoginEnabled
        password = (try? keychainService.loadPassword()) ?? ""
    }

    @discardableResult
    func save() -> Bool {
        do {
            try settingsStore.save(settings)

            if password.isEmpty {
                try keychainService.deletePassword()
            } else {
                try keychainService.savePassword(password)
            }

            do {
                try applyLaunchAtLoginPreference()
                statusMessage = "Settings saved."
            } catch {
                launchAtLoginEnabled = false
                var savedSettings = settings
                savedSettings.launchAtLoginEnabled = false
                try? settingsStore.save(savedSettings)
                statusMessage = "Settings saved. Launch at Login was disabled: \(error.localizedDescription)"
            }
            statusMessageIsError = false
            return true
        } catch {
            statusMessage = error.localizedDescription
            statusMessageIsError = true
            return false
        }
    }

    func clearCachedData() {
        historyStore.clearRecords()
        sharedElectricityStore.clearLatestRecord()
        WidgetCenter.shared.reloadAllTimelines()
        statusMessage = "Cached electricity data cleared."
        statusMessageIsError = false
    }

    private func applyLaunchAtLoginPreference() throws {
        #if os(macOS)
        if launchAtLoginEnabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
        #endif
    }
}
