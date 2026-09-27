import SwiftUI

@main
struct NewsTrackerApp: App {
    @State private var store = NewsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { await store.start() }
        }
    }
}
