import NewsCore
import SwiftUI

/// All detected price alerts, grouped by day, with a per-instrument filter.
struct PriceAlertsArchiveView: View {
    @Environment(MarketStore.self) private var market
    @Environment(\.openURL) private var openURL
    @State private var assetFilter: String?
    @State private var confirmClear = false

    private var records: [AlertRecord] {
        guard let assetFilter else { return market.recentAlerts }
        return market.recentAlerts.filter { $0.assetID == assetFilter }
    }

    var body: some View {
        let groups = DayGrouping.group(records) { $0.date }
        List {
            ForEach(groups, id: \.day) { group in
                Section(DayTitle.string(for: group.day)) {
                    ForEach(group.items) { record in
                        AlertRecordRow(record: record, showsDay: false)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let url = market.quoteURL(for: record) {
                                    openURL(url)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    market.deleteAlerts(ids: [record.id])
                                } label: {
                                    Label("Usuń", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .overlay {
            if records.isEmpty {
                ContentUnavailableView(
                    "Brak alertów",
                    systemImage: "bell.slash",
                    description: Text("Tu trafiają wszystkie wykryte nagłe zmiany cen z zakładki Rynki. Dotknij alertu, aby otworzyć notowania.")
                )
            }
        }
        .navigationTitle("Archiwum alertów")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        assetFilter = nil
                    } label: {
                        if assetFilter == nil {
                            Label("Wszystkie instrumenty", systemImage: "checkmark")
                        } else {
                            Text("Wszystkie instrumenty")
                        }
                    }
                    Divider()
                    ForEach(market.alertAssets) { option in
                        Button {
                            assetFilter = option.id
                        } label: {
                            if assetFilter == option.id {
                                Label(option.name, systemImage: "checkmark")
                            } else {
                                Text(option.name)
                            }
                        }
                    }
                } label: {
                    Image(systemName: assetFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .accessibilityLabel("Filtr instrumentów")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !market.recentAlerts.isEmpty {
                    Button("Wyczyść", role: .destructive) {
                        confirmClear = true
                    }
                }
            }
        }
        .confirmationDialog("Wyczyścić archiwum alertów?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Usuń wszystkie alerty (\(market.recentAlerts.count))", role: .destructive) {
                market.clearAlerts()
                assetFilter = nil
            }
        }
    }
}
