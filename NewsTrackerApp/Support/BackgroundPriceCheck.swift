import BackgroundTasks
import Foundation

/// Periodic price checks while the app is in the background (`BGAppRefreshTask`).
/// iOS decides when the task actually runs (typically every few hours, depending on
/// usage and battery), and it never runs after the user force-quits the app.
/// For reliable alerts use the GitHub Actions + ntfy watcher (see README).
enum BackgroundPriceCheck {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in `project.yml`.
    static let identifier = "com.example.newstracker.pricecheck"

    static func schedule(after interval: TimeInterval = 30 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
