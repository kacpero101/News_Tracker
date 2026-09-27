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
                        NavigationLink {
                            AssetDetailView(assetID: asset.id)
                        } label: {
                            AssetRow(
                                asset: asset,
                                series: market.series[asset.id],
                                chart: market.chartSeries[asset.id],
                                failure: market.failures[asset.id]
                            )
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editorTarget = EditorTarget(asset: asset)
                            } label: {
                                Label("Edytuj", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete { market.delete(at: $0) }
                    .onMove { market.move(from: $0, to: $1) }
                }

                if !market.recentAlerts.isEmpty {
                    Section("Ostatnie alerty") {
                        ForEach(market.recentAlerts.prefix(5)) { record in
                            AlertRecordRow(record: record)
                        }
                        NavigationLink {
                            PriceAlertsArchiveView()
                        } label: {
                            Label("Archiwum alertów (\(market.recentAlerts.count))", systemImage: "archivebox")
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
            .refreshable {
                await market.check()
                await market.loadCharts(force: true)
            }
            .task(id: market.assets.map(\.id)) {
                await market.loadCharts()
            }
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
    /// 7-day history for the sparkline.
    let chart: PriceSeries?
    let failure: String?

    private var sparklinePoints: [PricePoint] {
        PriceSeries.downsample(chart?.points(inLast: MarketStore.chartWindow) ?? [], maxPoints: 60)
    }

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading) {
                    Text(asset.name).font(.headline)
                    Text(asset.symbol).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                PriceChartView(points: sparklinePoints, compact: true)
                    .frame(width: 84, height: 34)
                if let latest = series?.latest ?? chart?.latest {
                    VStack(alignment: .trailing) {
                        Text("\(PriceAlertFormatter.price(latest.price)) \((series ?? chart)?.currency ?? "")")
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

struct RuleStatusRow: View {
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

struct AlertRecordRow: View {
    let record: AlertRecord
    /// In the archive the day is in the section header, so only the time is shown.
    var showsDay = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: record.isRise ? "arrow.up.right" : "arrow.down.right")
                    .foregroundStyle(record.isRise ? Color.green : Color.red)
                Text(record.title).font(.subheadline.bold())
            }
            Text(record.body).font(.caption).foregroundStyle(.secondary)
            Group {
                if showsDay {
                    Text(record.date, format: .dateTime.day().month().hour().minute())
                } else {
                    Text(record.date, format: .dateTime.hour().minute())
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
