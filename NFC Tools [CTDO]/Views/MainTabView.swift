import SwiftUI

struct MainTabView: View {
    @StateObject private var reader = NFCCardReader()
    @StateObject private var historyStore = ScanHistoryStore()
    @StateObject private var settings = SettingsStore()

    var body: some View {
        TabView {
            CheckTabView()
                .tabItem {
                    Label("확인", systemImage: "creditcard.viewfinder")
                }

            HistoryTabView()
                .tabItem {
                    Label("기록", systemImage: "clock.arrow.circlepath")
                }

            SettingsTabView()
                .tabItem {
                    Label("설정", systemImage: "gearshape")
                }
        }
        .environmentObject(reader)
        .environmentObject(historyStore)
        .environmentObject(settings)
        .preferredColorScheme(settings.theme.colorScheme)
        .environment(\.locale, settings.language.locale)
    }
}
