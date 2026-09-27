import NewsCore
import SwiftUI

/// Watchlist with latest prices, per-rule changes and recent alerts.
struct MarketsView: View {
    @Environment(MarketStore.self) private var market
    @State private var editorTarget: EditorTarget?

    /// Sheet target: an existing asset or a new one.
    struct EditorTarget: Identifiable {
        let id = UUID()
        let asset: WatchedAsset?
    }

    var body: some View {
        NavigationStack {
            List {
                if !market.notificationsEnabled {
                    Section {
                        Button {
                            Task { await market.setNotificationsEnabled(true) }
                        } label: {
                            Label("Włącz powiadomienia o zmianach cen", systemImage: "bell.badge")
                        }
                    } footer: {
                        Text("Bez tego zmiany będą widoczne tylko na tej liście.")
                    }
                }

                Section("Obserwowane") {
                    ForEach(market.assets) { asset in
                        Button {
                            editorTarget = EditorTarget(asset: asset)
                        } label: {
                            AssetRow(asset: asset, series: market.series[asset.id], failure: market.failures[asset.id])
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { market.delete(at: $0) }
                    .onMove { market.move(from: $0, to: $1) }
                }

                if !market.recentAlerts.isEmpty {
                    Section {
                        ForEach(market.recentAlerts.prefix(20)) { record in
                            AlertRecordRow(record: record)
                        }
                    } header: {
                        HStack {
                            Text("Ostatnie alerty")
                            Spacer()
                            Button("Wyczyść") { market.clearAlerts() }
                                .font(.caption)
                        }
                    }
                }
            }
            .overlay {
                if market.assets.isEmpty {
                    ContentUnavailableView {
                        Label("Brak obserwowanych", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Dodaj akcję, ETF lub kryptowalutę i ustaw próg zmiany.")
                    } actions: {
                        Button("Dodaj") { editorTarget = EditorTarget(asset: nil) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Rynki")
            .refreshable { await market.check() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if market.isChecking {
                        ProgressView()
                    } else if let lastCheck = market.lastCheck {
                        Text(lastCheck, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    EditButton()
                    Button {
                        editorTarget = EditorTarget(asset: nil)
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Dodaj")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                AssetEditorView(original: target.asset)
            }
        }
    }
}

private struct AssetRow: View {
    let asset: WatchedAsset
    let series: PriceSeries?
    let failure: String?

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text(asset.name).font(.headline)
                    Text(asset.symbol).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let latest = series?.latest {
                    VStack(alignment: .trailing) {
                        Text("\(PriceAlertFormatter.price(latest.price)) \(series?.currency ?? "")")
                            .font(.body.monospacedDigit())
                        Text(latest.date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(asset.rules) { rule in
                RuleStatusRow(rule: rule, points: series?.points ?? [], now: now)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct RuleStatusRow: View {
    let rule: AlertRule
    let points: [PricePoint]
    let now: Date

    var body: some View {
        let change = PriceMoveDetector.windowChange(points, window: rule.window, at: now)
        let triggered = PriceMoveDetector.evaluate(points, rule: rule, at: now)
        HStack(spacing: 6) {
            Image(systemName: triggered == nil ? "circle" : "bell.fill")
                .foregroundStyle(triggered == nil ? Color.secondary : Color.orange)
                .font(.caption2)
            Text("\(PriceAlertFormatter.window(rule.windowHours)): ")
            if let change {
                Text(PriceAlertFormatter.percent(change))
                    .foregroundStyle(change >= 0 ? Color.green : Color.red)
                    .monospacedDigit()
            } else {
                Text("–")
            }
            Text("(próg \(directionSymbol)\(PriceAlertFormatter.percent(rule.thresholdPercent, signed: false)))")
                .foregroundStyle(.secondary)
            if !rule.isEnabled {
                Text("wył.").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var directionSymbol: String {
        switch rule.direction {
        case .up: return "▲"
        case .down: return "▼"
        case .both: return "±"
        }
    }
}

private struct AlertRecordRow: View {
    let record: AlertRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: record.isRise ? "arrow.up.right" : "arrow.down.right")
                    .foregroundStyle(record.isRise ? Color.green : Color.red)
                Text(record.title).font(.subheadline.bold())
            }
            Text(record.body).font(.caption).foregroundStyle(.secondary)
            Text(record.date, format: .dateTime.day().month().hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
