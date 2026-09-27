import NewsCore
import SwiftUI

extension Topic {
    private static let builtInNames: [Topic: String] = [
        .finance: "Finanse", .politics: "Polityka", .breakthroughs: "Odkrycia",
        .crypto: "Kryptowaluty", .economy: "Gospodarka",
    ]
    private static let builtInSymbols: [Topic: String] = [
        .finance: "chart.line.uptrend.xyaxis", .politics: "building.columns", .breakthroughs: "atom",
        .crypto: "bitcoinsign.circle", .economy: "globe.europe.africa",
    ]
    private static let builtInColors: [Topic: Color] = [
        .finance: .green, .politics: .red, .breakthroughs: .purple, .crypto: .orange, .economy: .blue,
    ]

    var displayName: String {
        Topic.builtInNames[self] ?? TopicCatalog.shared.category(for: self)?.name ?? rawValue
    }

    var systemImage: String {
        Topic.builtInSymbols[self] ?? TopicCatalog.shared.category(for: self)?.symbol ?? "tag"
    }

    var color: Color {
        Topic.builtInColors[self] ?? CategoryPalette.color(named: TopicCatalog.shared.category(for: self)?.color)
    }
}

/// Icons and colors offered for custom categories.
enum CategoryPalette {
    struct NamedColor: Identifiable {
        let name: String
        let color: Color
        var id: String { name }
    }

    static let colors: [NamedColor] = [
        NamedColor(name: "teal", color: .teal), NamedColor(name: "indigo", color: .indigo),
        NamedColor(name: "pink", color: .pink), NamedColor(name: "mint", color: .mint),
        NamedColor(name: "cyan", color: .cyan), NamedColor(name: "brown", color: .brown),
        NamedColor(name: "yellow", color: .yellow), NamedColor(name: "gray", color: .gray),
    ]

    static let symbols = [
        "tag", "star", "bolt", "flame", "leaf", "heart", "cpu", "airplane", "car", "house",
        "cross.case", "shield", "sportscourt", "gamecontroller", "film", "music.note",
        "graduationcap", "globe", "newspaper", "briefcase",
    ]

    static func color(named name: String?) -> Color {
        colors.first { $0.name == name }?.color ?? .teal
    }
}

extension Language {
    var displayName: String {
        switch self {
        case .polish: return "Polski"
        case .english: return "Angielski"
        case .german: return "Niemiecki"
        }
    }

    var flag: String {
        switch self {
        case .polish: return "🇵🇱"
        case .english: return "🇬🇧"
        case .german: return "🇩🇪"
        }
    }
}

/// Section titles for archives: "Dziś", "Wczoraj", "2 maja 2024".
enum DayTitle {
    static func string(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Dziś" }
        if calendar.isDateInYesterday(day) { return "Wczoraj" }
        return day.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "pl_PL")))
    }
}
