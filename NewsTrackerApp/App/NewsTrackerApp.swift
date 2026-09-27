import SwiftUI
import UserNotifications

@main
struct NewsTrackerApp: App {
    @State private var store = NewsStore()
    @State private var marketStore = MarketStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(marketStore)
                .task { await store.start() }
                .task { await marketStore.check() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundPriceCheck.schedule()
            }
        }
        .backgroundTask(.appRefresh(BackgroundPriceCheck.identifier)) {
            await marketStore.check()
            BackgroundPriceCheck.schedule()
        }
    }
}
