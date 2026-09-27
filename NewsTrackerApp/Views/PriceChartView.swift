import Charts
import NewsCore
import SwiftUI

/// Price line chart: a compact sparkline (Markets list) or a full chart with axes
/// and touch selection (asset detail). Green when the price rose over the range, red otherwise.
struct PriceChartView: View {
    let points: [PricePoint]
    var compact = false
    @Binding var selectedDate: Date?

    init(points: [PricePoint], compact: Bool = false, selectedDate: Binding<Date?> = .constant(nil)) {
        self.points = points
        self.compact = compact
        _selectedDate = selectedDate
    }

    private var summary: PriceRangeSummary? { PriceSeries.summary(of: points) }

    private var trendColor: Color {
        (summary?.changePercent ?? 0) >= 0 ? .green : .red
    }

    /// Point closest to the touched date.
    private var selectedPoint: PricePoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        if compact {
            chart.allowsHitTesting(false)
        } else {
            chart.chartXSelection(value: $selectedDate)
        }
    }

    @ViewBuilder
    private var chart: some View {
        if let summary, points.count >= 2 {
            let padding = max((summary.high.price - summary.low.price) * 0.08, summary.high.price * 0.001)
            let domain = (summary.low.price - padding)...(summary.high.price + padding)
            Chart {
                ForEach(points, id: \.date) { point in
                    AreaMark(
                        x: .value("Czas", point.date),
                        yStart: .value("Minimum", domain.lowerBound),
                        yEnd: .value("Cena", point.price)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [trendColor.opacity(0.28), trendColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Czas", point.date),
                        y: .value("Cena", point.price)
                    )
                    .foregroundStyle(trendColor)
                    .lineStyle(StrokeStyle(lineWidth: compact ? 1.5 : 2))
                }
                if !compact, let selected = selectedPoint {
                    RuleMark(x: .value("Czas", selected.date))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                    PointMark(
                        x: .value("Czas", selected.date),
                        y: .value("Cena", selected.price)
                    )
                    .foregroundStyle(trendColor)
                }
            }
            .chartYScale(domain: domain)
            .chartXAxis(compact ? .hidden : .automatic)
            .chartYAxis(compact ? .hidden : .automatic)
            .accessibilityLabel("Wykres ceny, zmiana \(PriceAlertFormatter.percent(summary.changePercent))")
        } else if compact {
            Color.clear
        } else {
            ContentUnavailableView("Brak notowań w tym okresie", systemImage: "chart.xyaxis.line")
        }
    }
}
