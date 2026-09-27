import NewsCore
import SwiftUI

extension Topic {
    var displayName: String {
        switch self {
        case .finance: return "Finanse"
        case .politics: return "Polityka"
        case .breakthroughs: return "Odkrycia"
        case .crypto: return "Kryptowaluty"
        case .economy: return "Gospodarka"
        }
    }

    var systemImage: String {
        switch self {
        case .finance: return "chart.line.uptrend.xyaxis"
        case .politics: return "building.columns"
        case .breakthroughs: return "atom"
        case .crypto: return "bitcoinsign.circle"
        case .economy: return "globe.europe.africa"
        }
    }

    var color: Color {
        switch self {
        case .finance: return .green
        case .politics: return .red
        case .breakthroughs: return .purple
        case .crypto: return .orange
        case .economy: return .blue
        }
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
