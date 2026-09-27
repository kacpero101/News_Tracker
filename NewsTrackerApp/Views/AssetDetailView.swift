import NewsCore
import SwiftUI

/// Price chart (1 day / 7 days / 30 days), alert rules and recent alerts of one instrument.
struct AssetDetailView: View {
    enum Period: String, CaseIterable, Identifiable {
        case day = "1 dzień"
        case week = "7 dni"
        case month = "30 dni"

        var id: Self { self }

        var window: TimeInterval {
            switch self {
            case .day: return 86_400
            case .week: return 7 * 86_400
            case .month: return 30 * 86_400
            }
        }
    }

    @Environment(MarketStore.self) private var market
    @Environment(\.openURL) private var openURL
    let assetID: String

    @State private var period: Period = .week
    @State private var series: PriceSeries?
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var selectedDate: Date?
    @State private var showsEditor = false

    var body: some View {
        if let asset = market.asset(withID: assetID) {
            content(for: asset)
        } else {
            ContentUnavailableView("Instrument został usunięty", systemImage: "trash")
        }
    }

    /// Chart points of the selected period (counted back from the latest quote).
    private var chartPoints: [PricePoint] {
        guard let series else { return [] }
        return PriceSeries.downsample(series.points(inLast: period.window), maxPoints: 400)
    }

    private func content(for asset: WatchedAsset) -> some View {
        let points = chartPoints
        let summary = PriceSeries.summary(of: points)
        let currency = (series?.currency ?? market.series[asset.id]?.currency ?? asset.currency ?? "").uppercased()
        let alerts = market.recentAlerts.filter { $0.assetID == asset.id }
        return List {
            Section {
                header(summary: summary, points: points, currency: currency)
                Picker("Okres", selection: $period) {
                    ForEach(Period.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                chart(points: points)
                if let summary {
                    HStack {
                        Text("Min: \(PriceAlertFormatter.price(summary.low.price))")
                        Spacer()
                        Text("Maks: \(PriceAlertFormatter.price(summary.high.price))")
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Przesuń palcem po wykresie, aby zobaczyć cenę w danym momencie.")
            }

            Section("Reguły powiadomień") {
                ForEach(asset.rules) { rule in
                    RuleStatusRow(rule: rule, points: market.series[asset.id]?.points ?? series?.points ?? [], now: Date())
                }
            }

            if !alerts.isEmpty {
                Section("Ostatnie alerty") {
                    ForEach(alerts.prefix(5)) { record in
                        AlertRecordRow(record: record)
                    }
                }
            }

            if let url = asset.quoteURL {
                Section {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Otwórz notowania", systemImage: "safari")
                    }
                }
            }
        }
        .navigationTitle(asset.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edytuj") { showsEditor = true }
        }
        .sheet(isPresented: $showsEditor) {
            AssetEditorView(original: asset)
        }
        .task(id: period) {
            await load(asset, force: false)
        }
        .refreshable {
            await load(asset, force: true)
        }
    }

    @ViewBuilder
    private func header(summary: PriceRangeSummary?, points: [PricePoint], currency: String) -> some View {
        let selected = selectedDate.flatMap { date in
            points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        VStack(alignment: .leading, spacing: 4) {
            if let point = selected ?? summary?.last {
                Text("\(PriceAlertFormatter.price(point.price)) \(currency)")
                    .font(.title2.bold().monospacedDigit())
                Text(point.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let summary, selected == nil {
                Text("\(PriceAlertFormatter.percent(summary.changePercent)) w okresie \(period.rawValue)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(summary.changePercent >= 0 ? Color.green : Color.red)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func chart(points: [PricePoint]) -> some View {
        if isLoading && points.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
        } else if let loadError, points.isEmpty {
            Text(loadError)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            PriceChartView(points: points, selectedDate: $selectedDate)
                .frame(height: 240)
                .padding(.vertical, 4)
        }
    }

    private func load(_ asset: WatchedAsset, force: Bool) async {
        selectedDate = nil
        // The 7-day chart is usually already downloaded for the Markets list.
        if period == .week, !force, let cached = market.chartSeries[asset.id] {
            series = cached
            loadError = nil
            return
        }
        series = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await market.history(for: asset, window: period.window)
            // A newer period was selected meanwhile – keep its data.
            guard !Task.isCancelled else { return }
            series = loaded
            loadError = nil
        } catch {
            guard !Task.isCancelled else { return }
            loadError = "Nie udało się pobrać notowań: \(error.localizedDescription)"
        }
    }
}
