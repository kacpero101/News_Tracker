import Foundation
import NewsCore

// price-watch – checks watched prices and sends ntfy notifications about sudden moves.
//
// Usage:
//   price-watch [--config alerts.json] [--state state.json] [--interval-minutes 60] [--dry-run] [--test]
// Environment:
//   NTFY_TOPIC   ntfy topic to publish to (required unless --dry-run)
//   NTFY_SERVER  ntfy server, default https://ntfy.sh

struct Options {
    var configPath = "alerts.json"
    var statePath: String?
    var intervalMinutes: Double = 60
    var dryRun = false
    var sendTest = false
}

func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    var iterator = arguments.dropFirst().makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--config": options.configPath = iterator.next() ?? options.configPath
        case "--state": options.statePath = iterator.next()
        case "--interval-minutes": options.intervalMinutes = iterator.next().flatMap(Double.init) ?? options.intervalMinutes
        case "--dry-run": options.dryRun = true
        case "--test": options.sendTest = true
        case "--help", "-h":
            print("price-watch [--config alerts.json] [--state state.json] [--interval-minutes 60] [--dry-run] [--test]")
            exit(0)
        default:
            fail("Unknown argument: \(argument)")
        }
    }
    return options
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let options = parseOptions(CommandLine.arguments)
let environment = ProcessInfo.processInfo.environment
let topic = environment["NTFY_TOPIC"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
let server = environment["NTFY_SERVER"].flatMap { $0.isEmpty ? nil : URL(string: $0) } ?? URL(string: "https://ntfy.sh")!
let notifier: NtfyNotifier? = topic.isEmpty || options.dryRun ? nil : NtfyNotifier(topic: topic, server: server)

if options.sendTest {
    guard let notifier else { fail("Set NTFY_TOPIC to send a test notification") }
    do {
        try await notifier.sendTest()
        print("Test notification sent.")
        exit(0)
    } catch {
        fail("Could not send test notification: \(error.localizedDescription)")
    }
}

let configuration: PriceWatchConfiguration
do {
    configuration = try PriceWatchConfiguration.decode(from: Data(contentsOf: URL(fileURLWithPath: options.configPath)))
} catch {
    fail("Cannot read \(options.configPath): \(error)")
}

let stateStore = options.statePath.map { JSONFileStore<PriceWatchState>(fileURL: URL(fileURLWithPath: $0)) }
let now = Date()
let storedLastCheck = (try? stateStore?.load())??.lastCheck
// Without state (first run or lost cache) assume the previous run happened one interval ago.
let previousCheck = storedLastCheck ?? now.addingTimeInterval(-options.intervalMinutes * 60)

print("Checking \(configuration.assets.count) assets (previous check: \(previousCheck))")
let report = await PriceWatchRunner().run(assets: configuration.assets, now: now, previousCheck: previousCheck)

for asset in configuration.assets {
    if let error = report.failures[asset.id] {
        print("⚠️  \(asset.name) (\(asset.symbol)): \(error)")
    } else if let latest = report.series[asset.id]?.latest {
        print("✓  \(asset.name) (\(asset.symbol)): \(PriceAlertFormatter.price(latest.price)) @ \(latest.date)")
    }
}

for alert in report.alerts {
    print("🔔 \(PriceAlertFormatter.title(for: alert)) – \(PriceAlertFormatter.body(for: alert))")
}
if report.alerts.isEmpty {
    print("No new price alerts.")
}

var exitCode: Int32 = 0
if let notifier {
    do {
        try await notifier.deliver(report.alerts)
        if !report.alerts.isEmpty { print("Sent \(report.alerts.count) notification(s) via ntfy.") }
    } catch {
        FileHandle.standardError.write(Data("error: ntfy delivery failed: \(error.localizedDescription)\n".utf8))
        exitCode = 1
    }
} else if !report.alerts.isEmpty {
    print("Notifications not sent (dry run or NTFY_TOPIC not set).")
}

// Only advance the state when delivery worked, so alerts are retried next time.
if exitCode == 0 {
    try? stateStore?.save(PriceWatchState(lastCheck: now))
}
if report.failures.count == configuration.assets.count && !configuration.assets.isEmpty {
    FileHandle.standardError.write(Data("error: all assets failed\n".utf8))
    exitCode = 1
}
exit(exitCode)
