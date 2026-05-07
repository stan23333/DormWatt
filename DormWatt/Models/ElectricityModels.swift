//
//  ElectricityModels.swift
//  DormWatt
//

import Foundation

struct ElectricityRecord: Codable, Equatable, Identifiable {
    var id: Date { timestamp }

    let balance: Double
    let rawText: String
    let timestamp: Date
}

enum DormWattSharedConfiguration {
    static let sharedDefaultsSuiteName = "group.com.example.DormWatt"
    static let widgetKind = "DormWattWidget"

    static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: sharedDefaultsSuiteName) ?? .standard
    }
}

struct AppSettings: Codable, Equatable {
    var loginURL: String
    var balancePageURL: String
    var username: String
    var usernameSelector: String
    var passwordSelector: String
    var loginButtonSelector: String
    var balanceTextSelector: String
    var refreshIntervalMinutes: Int
    var lowBalanceThreshold: Double
    var backgroundRefreshEnabled: Bool
    var launchAtLoginEnabled: Bool

    init(
        loginURL: String,
        balancePageURL: String,
        username: String,
        usernameSelector: String,
        passwordSelector: String,
        loginButtonSelector: String,
        balanceTextSelector: String,
        refreshIntervalMinutes: Int,
        lowBalanceThreshold: Double,
        backgroundRefreshEnabled: Bool = true,
        launchAtLoginEnabled: Bool = false
    ) {
        self.loginURL = loginURL
        self.balancePageURL = balancePageURL
        self.username = username
        self.usernameSelector = usernameSelector
        self.passwordSelector = passwordSelector
        self.loginButtonSelector = loginButtonSelector
        self.balanceTextSelector = balanceTextSelector
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.lowBalanceThreshold = lowBalanceThreshold
        self.backgroundRefreshEnabled = backgroundRefreshEnabled
        self.launchAtLoginEnabled = launchAtLoginEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaultSettings = AppSettings.default

        loginURL = try container.decodeIfPresent(String.self, forKey: .loginURL) ?? defaultSettings.loginURL
        balancePageURL = try container.decodeIfPresent(String.self, forKey: .balancePageURL) ?? defaultSettings.balancePageURL
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? defaultSettings.username
        usernameSelector = try container.decodeIfPresent(String.self, forKey: .usernameSelector) ?? defaultSettings.usernameSelector
        passwordSelector = try container.decodeIfPresent(String.self, forKey: .passwordSelector) ?? defaultSettings.passwordSelector
        loginButtonSelector = try container.decodeIfPresent(String.self, forKey: .loginButtonSelector) ?? defaultSettings.loginButtonSelector
        balanceTextSelector = try container.decodeIfPresent(String.self, forKey: .balanceTextSelector) ?? defaultSettings.balanceTextSelector
        refreshIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? defaultSettings.refreshIntervalMinutes
        lowBalanceThreshold = try container.decodeIfPresent(Double.self, forKey: .lowBalanceThreshold) ?? defaultSettings.lowBalanceThreshold
        backgroundRefreshEnabled = try container.decodeIfPresent(Bool.self, forKey: .backgroundRefreshEnabled) ?? defaultSettings.backgroundRefreshEnabled
        launchAtLoginEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? defaultSettings.launchAtLoginEnabled
    }

    static let `default` = AppSettings(
        loginURL: "",
        balancePageURL: "",
        username: "",
        usernameSelector: "input[name='username']",
        passwordSelector: "input[type='password']",
        loginButtonSelector: "button[type='submit']",
        balanceTextSelector: "#balance",
        refreshIntervalMinutes: 15,
        lowBalanceThreshold: 5,
        backgroundRefreshEnabled: true,
        launchAtLoginEnabled: false
    )
}

enum CollectorState: Equatable {
    case idle
    case loadingLoginPage
    case fillingCredentials
    case submittingLogin
    case navigatingToBalancePage
    case selectingService
    case extractingBalance
    case success
    case failure(String)

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .loadingLoginPage:
            return "Loading login page"
        case .fillingCredentials:
            return "Filling credentials"
        case .submittingLogin:
            return "Submitting login"
        case .navigatingToBalancePage:
            return "Opening balance page"
        case .selectingService:
            return "Selecting electricity service"
        case .extractingBalance:
            return "Extracting balance"
        case .success:
            return "Updated"
        case .failure:
            return "Failed"
        }
    }

    var message: String? {
        if case let .failure(message) = self {
            return message
        }
        return nil
    }
}

enum DormWattError: LocalizedError, Equatable {
    case invalidLoginURL
    case missingRequiredSettings
    case missingPassword
    case missingElement(String)
    case emptyExtractedText
    case parseFailure(String)
    case navigationFailure(String)
    case javaScriptFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidLoginURL:
            return "Login URL is invalid."
        case .missingRequiredSettings:
            return "Please fill in the login URL, username, and required selectors."
        case .missingPassword:
            return "Please save the password in Settings first."
        case let .missingElement(selector):
            return "Could not find an element matching selector: \(selector)"
        case .emptyExtractedText:
            return "The selected balance element did not contain text."
        case let .parseFailure(text):
            return "Could not parse a balance from: \(text)"
        case let .navigationFailure(message):
            return "Navigation failed: \(message)"
        case let .javaScriptFailure(message):
            return "JavaScript failed: \(message)"
        }
    }
}
