//
//  ContentView.swift
//  DormWatt
//
//

import SwiftUI

struct ContentView: View {
    @StateObject private var dashboardViewModel: DashboardViewModel
    @StateObject private var settingsViewModel: SettingsViewModel
    @StateObject private var backgroundRefreshCoordinator: BackgroundRefreshCoordinator

    init() {
        let settingsStore = AppSettingsStore()
        let keychainService = KeychainService()
        let historyStore = ElectricityHistoryStore()
        let sharedElectricityStore = SharedElectricityStore()
        let refreshManager = ElectricityRefreshManager(
            settingsStore: settingsStore,
            keychainService: keychainService,
            recordStore: sharedElectricityStore,
            collector: WKWebViewElectricityCollector()
        )

        _dashboardViewModel = StateObject(wrappedValue: DashboardViewModel(
            dataProvider: CollectorElectricityDataProvider(
                refreshManager: refreshManager,
                historyStore: historyStore
            ),
            settingsStore: settingsStore
        ))
        _settingsViewModel = StateObject(wrappedValue: SettingsViewModel(
            settingsStore: settingsStore,
            keychainService: keychainService
        ))
        _backgroundRefreshCoordinator = StateObject(wrappedValue: BackgroundRefreshCoordinator(
            settingsStore: settingsStore,
            refreshManager: refreshManager,
            historyStore: historyStore
        ))
    }

    var body: some View {
        content
            .task {
                backgroundRefreshCoordinator.start()
            }
            .onReceive(backgroundRefreshCoordinator.$latestRecord.compactMap { $0 }) { record in
                dashboardViewModel.applyBackgroundRecord(record)
            }
        #if os(macOS)
            .frame(minWidth: 760, minHeight: 520)
        #endif
    }

    private var content: some View {
        TabView {
            NavigationStack {
                DashboardView(viewModel: dashboardViewModel)
            }
            .tabItem {
                Label("Dashboard", systemImage: "bolt.fill")
            }

            NavigationStack {
                SettingsView(viewModel: settingsViewModel) {
                    dashboardViewModel.clearCachedData()
                } onSettingsSaved: {
                    backgroundRefreshCoordinator.reloadConfiguration()
                } onRefreshNow: {
                    Task {
                        await backgroundRefreshCoordinator.refreshNow()
                    }
                }
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
