//
//  DormWattTests.swift
//  DormWattTests
//

import XCTest
@testable import DormWatt

final class DormWattTests: XCTestCase {
    func testRegexBalanceParserMatchesSupportedLabels() throws {
        let parser = RegexBalanceParser()

        XCTAssertEqual(try parser.parseBalance(from: "剩余电费：12.34"), 12.34, accuracy: 0.001)
        XCTAssertEqual(try parser.parseBalance(from: "余额：12.34"), 12.34, accuracy: 0.001)
        XCTAssertEqual(try parser.parseBalance(from: "剩余金额：12.34 元"), 12.34, accuracy: 0.001)
        XCTAssertEqual(try parser.parseBalance(from: "剩余电量 16.54 度"), 16.54, accuracy: 0.001)
        XCTAssertEqual(try parser.parseBalance(from: "balance: 12.34"), 12.34, accuracy: 0.001)
        XCTAssertEqual(try parser.parseBalance(from: "remaining: 12.34"), 12.34, accuracy: 0.001)
    }

    func testDefaultSettingsUsePublicPlaceholders() {
        XCTAssertEqual(AppSettings.default.loginURL, "")
        XCTAssertEqual(AppSettings.default.usernameSelector, "input[name='username']")
        XCTAssertEqual(AppSettings.default.passwordSelector, "input[type='password']")
        XCTAssertEqual(AppSettings.default.loginButtonSelector, "button[type='submit']")
        XCTAssertEqual(AppSettings.default.balanceTextSelector, "#balance")
        XCTAssertEqual(AppSettings.default.refreshIntervalMinutes, 15)
        XCTAssertEqual(AppSettings.default.lowBalanceThreshold, 5)
        XCTAssertTrue(AppSettings.default.backgroundRefreshEnabled)
        XCTAssertFalse(AppSettings.default.launchAtLoginEnabled)
    }

    func testAppSettingsDecodeKeepsDefaultsForNewBackgroundFields() throws {
        let json = """
        {
          "loginURL": "https://example.edu/login",
          "balancePageURL": "",
          "username": "student",
          "usernameSelector": "#username",
          "passwordSelector": "#password",
          "loginButtonSelector": "#login",
          "balanceTextSelector": "#balance",
          "refreshIntervalMinutes": 15,
          "lowBalanceThreshold": 5
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertTrue(settings.backgroundRefreshEnabled)
        XCTAssertFalse(settings.launchAtLoginEnabled)
    }

    func testRegexBalanceParserRejectsInvalidText() {
        let parser = RegexBalanceParser()

        XCTAssertThrowsError(try parser.parseBalance(from: "no balance here"))
    }

    func testAppSettingsStoreSavesAndLoadsValues() throws {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        let settings = AppSettings(
            loginURL: "https://example.edu/login",
            balancePageURL: "https://example.edu/balance",
            username: "student",
            usernameSelector: "#username",
            passwordSelector: "#password",
            loginButtonSelector: "#login",
            balanceTextSelector: "#balance",
            refreshIntervalMinutes: 30,
            lowBalanceThreshold: 8.5
        )

        try store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testSharedElectricityStoreSavesLatestRecord() throws {
        let defaults = makeDefaults()
        let store = SharedElectricityStore(defaults: defaults, fallbackDefaults: nil)
        let record = ElectricityRecord(balance: 21.5, rawText: "余额：21.5", timestamp: Date())

        try store.saveLatestRecord(record)

        XCTAssertEqual(store.loadLatestRecord(), record)
    }

    func testSharedElectricityStoreClearsLatestRecord() throws {
        let defaults = makeDefaults()
        let store = SharedElectricityStore(defaults: defaults, fallbackDefaults: nil)
        let record = ElectricityRecord(balance: 21.5, rawText: "余额：21.5", timestamp: Date())

        try store.saveLatestRecord(record)
        store.clearLatestRecord()

        XCTAssertNil(store.loadLatestRecord())
    }

    func testElectricityHistoryStoreSavesLoadsAndSortsRecords() throws {
        let defaults = makeDefaults()
        let store = ElectricityHistoryStore(defaults: defaults, fallbackDefaults: nil)
        let now = Date()
        let newer = ElectricityRecord(balance: 18, rawText: "newer", timestamp: now)
        let older = ElectricityRecord(balance: 20, rawText: "older", timestamp: now.addingTimeInterval(-900))

        try store.replaceRecords([newer, older])

        XCTAssertEqual(store.loadRecords(), [older, newer])
        XCTAssertEqual(store.latestRecord(), newer)
    }

    func testElectricityHistoryStoreUpsertsRecordByTimestamp() throws {
        let defaults = makeDefaults()
        let store = ElectricityHistoryStore(defaults: defaults, fallbackDefaults: nil)
        let timestamp = Date()
        let original = ElectricityRecord(balance: 18, rawText: "original", timestamp: timestamp)
        let replacement = ElectricityRecord(balance: 17, rawText: "replacement", timestamp: timestamp)

        try store.saveRecord(original)
        try store.saveRecord(replacement)

        XCTAssertEqual(store.loadRecords(), [replacement])
    }

    func testElectricityHistoryStoreClearsRecords() throws {
        let defaults = makeDefaults()
        let store = ElectricityHistoryStore(defaults: defaults, fallbackDefaults: nil)
        let record = ElectricityRecord(balance: 18, rawText: "cached", timestamp: Date())

        try store.saveRecord(record)
        store.clearRecords()

        XCTAssertTrue(store.loadRecords().isEmpty)
        XCTAssertNil(store.latestRecord())
    }

    func testElectricityAnalyticsConsumptionIgnoresRechargeIncreases() {
        let now = Date()
        let records = [
            ElectricityRecord(balance: 20, rawText: "", timestamp: now.addingTimeInterval(-3600)),
            ElectricityRecord(balance: 18, rawText: "", timestamp: now.addingTimeInterval(-2700)),
            ElectricityRecord(balance: 25, rawText: "", timestamp: now.addingTimeInterval(-1800)),
            ElectricityRecord(balance: 23.5, rawText: "", timestamp: now.addingTimeInterval(-900))
        ]

        let consumption = ElectricityAnalytics.consumption(in: .lastHour, from: records, now: now)

        XCTAssertEqual(consumption, 3.5, accuracy: 0.001)
    }

    func testElectricityAnalyticsConsumptionHandlesSparseData() {
        let now = Date()

        XCTAssertEqual(ElectricityAnalytics.consumption(in: .lastHour, from: [], now: now), 0)
        XCTAssertEqual(ElectricityAnalytics.consumption(
            in: .lastHour,
            from: [ElectricityRecord(balance: 20, rawText: "", timestamp: now)],
            now: now
        ), 0)
    }

    func testElectricityTimeRangeStartsAtMondayAndMonthStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date("2026-05-06T12:00:00Z")

        XCTAssertEqual(ElectricityTimeRange.weekToDate.startDate(from: now, calendar: calendar), date("2026-05-04T00:00:00Z"))
        XCTAssertEqual(ElectricityTimeRange.monthToDate.startDate(from: now, calendar: calendar), date("2026-05-01T00:00:00Z"))
    }

    func testElectricityAnalyticsLowBalanceThreshold() {
        XCTAssertFalse(ElectricityAnalytics.isLowBalance(record: nil, threshold: 5))
        XCTAssertTrue(ElectricityAnalytics.isLowBalance(
            record: ElectricityRecord(balance: 5, rawText: "", timestamp: Date()),
            threshold: 5
        ))
        XCTAssertFalse(ElectricityAnalytics.isLowBalance(
            record: ElectricityRecord(balance: 5.01, rawText: "", timestamp: Date()),
            threshold: 5
        ))
    }

    func testMockRecordsCoverApproximatelyOneMonth() {
        let now = date("2026-05-06T12:00:00Z")
        let records = ElectricityAnalytics.mockRecords(now: now)

        XCTAssertGreaterThan(records.count, 2800)
        XCTAssertLessThanOrEqual(abs(records.last?.timestamp.timeIntervalSince(now) ?? 999), 900)
    }

    @MainActor
    func testDashboardViewModelLoadsAndRefreshesMockProvider() async throws {
        let defaults = makeDefaults()
        let settingsStore = AppSettingsStore(defaults: defaults)
        try settingsStore.save(validSettings())
        let provider = FakeDataProvider(records: [
            ElectricityRecord(balance: 18.2, rawText: "mock", timestamp: Date())
        ])
        let viewModel = DashboardViewModel(dataProvider: provider, settingsStore: settingsStore)

        await viewModel.load()
        XCTAssertEqual(viewModel.latestRecord?.balance, 18.2)

        await viewModel.refresh()
        XCTAssertEqual(viewModel.latestRecord?.balance, 17.9)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testDashboardViewModelClearsCachedState() async throws {
        let defaults = makeDefaults()
        let settingsStore = AppSettingsStore(defaults: defaults)
        try settingsStore.save(validSettings())
        let provider = FakeDataProvider(records: [
            ElectricityRecord(balance: 18.2, rawText: "mock", timestamp: Date())
        ])
        let viewModel = DashboardViewModel(dataProvider: provider, settingsStore: settingsStore)

        await viewModel.load()
        viewModel.clearCachedData()

        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertNil(viewModel.latestRecord)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.state, .idle)
    }

    @MainActor
    func testSettingsViewModelClearsCachedStoresWithoutClearingSettings() throws {
        let defaults = makeDefaults()
        let settingsStore = AppSettingsStore(defaults: defaults)
        let historyStore = ElectricityHistoryStore(defaults: defaults, fallbackDefaults: nil)
        let sharedStore = SharedElectricityStore(defaults: defaults, fallbackDefaults: nil)
        let settings = validSettings()
        let record = ElectricityRecord(balance: 18.2, rawText: "cached", timestamp: Date())
        try settingsStore.save(settings)
        try historyStore.saveRecord(record)
        try sharedStore.saveLatestRecord(record)
        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            keychainService: FakePasswordStore(),
            historyStore: historyStore,
            sharedElectricityStore: sharedStore
        )

        viewModel.clearCachedData()

        XCTAssertTrue(historyStore.loadRecords().isEmpty)
        XCTAssertNil(sharedStore.loadLatestRecord())
        XCTAssertEqual(settingsStore.load(), settings)
        XCTAssertEqual(viewModel.statusMessage, "Cached electricity data cleared.")
        XCTAssertFalse(viewModel.statusMessageIsError)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "DormWattTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func validSettings() -> AppSettings {
        AppSettings(
            loginURL: "https://example.edu/login",
            balancePageURL: "",
            username: "student",
            usernameSelector: "#username",
            passwordSelector: "#password",
            loginButtonSelector: "#login",
            balanceTextSelector: "#balance",
            refreshIntervalMinutes: 15,
            lowBalanceThreshold: 5
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private final class FakeDataProvider: ElectricityDataProvider {
    var records: [ElectricityRecord]

    init(records: [ElectricityRecord]) {
        self.records = records
    }

    @MainActor
    func loadHistory() async throws -> [ElectricityRecord] {
        records
    }

    @MainActor
    func refresh() async throws -> ElectricityRecord {
        let record = ElectricityRecord(balance: 17.9, rawText: "refresh", timestamp: Date())
        records.append(record)
        return record
    }
}

private final class FakePasswordStore: PasswordStore {
    var password: String?

    func loadPassword() throws -> String? {
        password
    }

    func savePassword(_ password: String) throws {
        self.password = password
    }

    func deletePassword() throws {
        password = nil
    }
}
