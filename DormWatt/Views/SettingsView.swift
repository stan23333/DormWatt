//
//  SettingsView.swift
//  DormWatt
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    var onClearCache: () -> Void = {}
    var onSettingsSaved: () -> Void = {}
    var onRefreshNow: () -> Void = {}

    @State private var showsDebugWebView = false
    @State private var showsClearCacheConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: "Monitoring", footer: "The app refreshes every 15 minutes while it is running. Widget refresh timing is handled by the system.") {
                    HStack {
                        Text("Refresh interval")
                        Spacer()
                        Stepper("\(viewModel.refreshIntervalMinutes) min", value: $viewModel.refreshIntervalMinutes, in: 15...1440, step: 15)
                    }

                    Toggle("Background refresh", isOn: $viewModel.backgroundRefreshEnabled)

                    #if os(macOS)
                    Toggle("Launch at Login", isOn: $viewModel.launchAtLoginEnabled)
                    #endif

                    HStack {
                        Text("Warning line")
                        Spacer()
                        TextField("Threshold", value: $viewModel.lowBalanceThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                        Text("kWh")
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsSection(title: "Website") {
                    TextField("Login URL", text: $viewModel.loginURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Balance Page URL (optional)", text: $viewModel.balancePageURL)
                        .textFieldStyle(.roundedBorder)
                }

                SettingsSection(title: "Credentials") {
                    TextField("Username", text: $viewModel.username)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                }

                SettingsSection(title: "Selectors") {
                    TextField("Username CSS selector", text: $viewModel.usernameSelector)
                        .textFieldStyle(.roundedBorder)
                    TextField("Password CSS selector", text: $viewModel.passwordSelector)
                        .textFieldStyle(.roundedBorder)
                    TextField("Login button CSS selector", text: $viewModel.loginButtonSelector)
                        .textFieldStyle(.roundedBorder)
                    TextField("Balance text CSS selector", text: $viewModel.balanceTextSelector)
                        .textFieldStyle(.roundedBorder)
                }

                SettingsSection(title: "Storage") {
                    SettingsValueRow(title: "Cache", value: "Local UserDefaults")

                    Button(role: .destructive) {
                        showsClearCacheConfirmation = true
                    } label: {
                        Label("Clear Cached Electricity Data", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onRefreshNow()
                    } label: {
                        Label("Refresh Widget Now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Text("Clears saved balance history and the latest widget reading. Settings and password are kept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                #if os(macOS)
                SettingsSection(title: "Advanced") {
                    Button {
                        showsDebugWebView = true
                    } label: {
                        Label("Open Debug WebView", systemImage: "safari")
                    }
                }
                #endif

                HStack(spacing: 12) {
                    Button("Save Settings") {
                        if viewModel.save() {
                            onSettingsSaved()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: [.command])

                    if let statusMessage = viewModel.statusMessage {
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundColor(viewModel.statusMessageIsError ? .red : .secondary)
                    }
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(SettingsColors.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .confirmationDialog(
            "Clear cached electricity data?",
            isPresented: $showsClearCacheConfirmation
        ) {
            Button("Clear Cache", role: .destructive) {
                viewModel.clearCachedData()
                onClearCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes saved electricity history and the latest widget value. Your website settings and password will remain.")
        }
        #if os(macOS)
        .sheet(isPresented: $showsDebugWebView) {
            DebugWebViewScreen(settingsViewModel: viewModel)
                .frame(minWidth: 960, minHeight: 640)
        }
        #endif
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                content
            }

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private enum SettingsColors {
    static var background: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var panel: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}
