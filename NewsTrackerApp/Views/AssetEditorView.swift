import NewsCore
import SwiftUI

/// Add or edit a watched asset and its alert rules.
struct AssetEditorView: View {
    @Environment(MarketStore.self) private var market
    @Environment(\.dismiss) private var dismiss

    let original: WatchedAsset?

    @State private var name = ""
    @State private var symbol = ""
    @State private var kind: AssetKind = .stock
    @State private var provider: PriceProviderID = .yahoo
    @State private var currency = "usd"
    @State private var rules: [AlertRule] = [AlertRule(windowHours: 24, thresholdPercent: 5)]
    @State private var validation: String?
    @State private var isValidating = false

    static let windowOptions: [Double] = [1, 2, 4, 6, 12, 24, 48, 72, 168]

    init(original: WatchedAsset?) {
        self.original = original
        if let asset = original {
            _name = State(initialValue: asset.name)
            _symbol = State(initialValue: asset.symbol)
            _kind = State(initialValue: asset.kind)
            _provider = State(initialValue: asset.provider)
            _currency = State(initialValue: asset.currency ?? "usd")
            _rules = State(initialValue: asset.rules)
        }
    }

    private var trimmedSymbol: String { symbol.trimmingCharacters(in: .whitespaces) }

    private var draft: WatchedAsset {
        WatchedAsset(
            id: original?.id,
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? trimmedSymbol : name.trimmingCharacters(in: .whitespaces),
            symbol: trimmedSymbol,
            kind: kind,
            provider: provider,
            currency: provider == .coingecko ? currency.lowercased() : nil,
            rules: rules
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nazwa (np. Bitcoin)", text: $name)
                    Picker("Rodzaj", selection: $kind) {
                        Text("Akcja").tag(AssetKind.stock)
                        Text("ETF").tag(AssetKind.etf)
                        Text("Kryptowaluta").tag(AssetKind.crypto)
                        Text("Indeks").tag(AssetKind.index)
                    }
                    .onChange(of: kind) { _, newKind in
                        if original == nil {
                            provider = newKind == .crypto ? .coingecko : .yahoo
                        }
                    }
                    Picker("Źródło cen", selection: $provider) {
                        Text("Yahoo Finance").tag(PriceProviderID.yahoo)
                        Text("CoinGecko").tag(PriceProviderID.coingecko)
                    }
                    TextField(provider == .yahoo ? "Symbol (np. AAPL, SPY, PKN.WA)" : "ID monety (np. bitcoin)", text: $symbol)
                        .textInputAutocapitalization(provider == .yahoo ? TextInputAutocapitalization.characters : TextInputAutocapitalization.never)
                        .autocorrectionDisabled()
                    if provider == .coingecko {
                        Picker("Waluta", selection: $currency) {
                            Text("USD").tag("usd")
                            Text("EUR").tag("eur")
                            Text("PLN").tag("pln")
                        }
                    }
                    Button {
                        Task { await validate() }
                    } label: {
                        HStack {
                            Text("Sprawdź symbol")
                            if isValidating { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(trimmedSymbol.isEmpty || isValidating)
                    if let validation {
                        Text(validation).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Instrument")
                } footer: {
                    Text(provider == .yahoo
                         ? "Symbole Yahoo: USA – AAPL, SPY; GPW – PKN.WA, CDR.WA; Xetra – SAP.DE; kryptowaluty – BTC-USD."
                         : "ID z adresu strony CoinGecko, np. coingecko.com/en/coins/bitcoin → bitcoin.")
                }

                Section {
                    ForEach($rules) { $rule in
                        RuleEditor(rule: $rule)
                    }
                    .onDelete { rules.remove(atOffsets: $0) }
                    Button {
                        rules.append(AlertRule(id: UUID().uuidString, windowHours: 24, thresholdPercent: 5))
                    } label: {
                        Label("Dodaj regułę", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Reguły powiadomień")
                } footer: {
                    Text("Powiadomienie, gdy cena zmieni się o co najmniej podany procent w wybranym oknie czasu (liczone od najniższej/najwyższej ceny w oknie). Każdy ruch zgłaszany jest raz.")
                }
            }
            .navigationTitle(original == nil ? "Nowy instrument" : "Edycja")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        market.upsert(draft)
                        dismiss()
                    }
                    .disabled(trimmedSymbol.isEmpty || rules.isEmpty)
                }
            }
        }
    }

    private func validate() async {
        isValidating = true
        defer { isValidating = false }
        switch await market.validate(draft) {
        case let .success(point):
            validation = "OK – ostatnia cena: \(PriceAlertFormatter.price(point.price))"
        case let .failure(error):
            validation = "Błąd: \(error.localizedDescription)"
        }
    }
}

private struct RuleEditor: View {
    @Binding var rule: AlertRule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Okno czasu", selection: $rule.windowHours) {
                ForEach(windowOptions, id: \.self) { hours in
                    Text(PriceAlertFormatter.window(hours)).tag(hours)
                }
            }
            Stepper(value: $rule.thresholdPercent, in: 0.5...50, step: 0.5) {
                Text("Zmiana co najmniej \(PriceAlertFormatter.percent(rule.thresholdPercent, signed: false))")
            }
            Picker("Kierunek", selection: $rule.direction) {
                Text("Wzrost").tag(MoveDirection.up)
                Text("Spadek").tag(MoveDirection.down)
                Text("Oba").tag(MoveDirection.both)
            }
            .pickerStyle(.segmented)
            Toggle("Aktywna", isOn: $rule.isEnabled)
        }
        .padding(.vertical, 4)
    }

    /// Standard windows plus the rule's current value (e.g. from an imported config).
    private var windowOptions: [Double] {
        Array(Set(AssetEditorView.windowOptions + [rule.windowHours])).sorted()
    }
}
