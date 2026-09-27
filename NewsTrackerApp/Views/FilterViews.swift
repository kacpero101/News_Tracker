import NewsCore
import SwiftUI

/// Horizontally scrolling topic chips (multi-select; none selected = all topics).
struct TopicFilterBar: View {
    @Environment(NewsStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Wszystkie", systemImage: "square.grid.2x2", color: .accentColor, isOn: store.query.topics.isEmpty) {
                    store.query.topics = []
                }
                ForEach(Topic.allCases, id: \.self) { topic in
                    chip(title: topic.displayName, systemImage: topic.systemImage, color: topic.color, isOn: store.query.topics.contains(topic)) {
                        store.toggleTopic(topic)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func chip(title: String, systemImage: String, color: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? color : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Toolbar menu for choosing languages (multi-select; none selected = all languages).
struct LanguageFilterMenu: View {
    @Environment(NewsStore.self) private var store

    var body: some View {
        Menu {
            Button {
                store.query.languages = []
            } label: {
                if store.query.languages.isEmpty {
                    Label("Wszystkie języki", systemImage: "checkmark")
                } else {
                    Text("Wszystkie języki")
                }
            }
            Divider()
            ForEach(Language.allCases, id: \.self) { language in
                Button {
                    store.toggleLanguage(language)
                } label: {
                    if store.query.languages.contains(language) {
                        Label("\(language.flag) \(language.displayName)", systemImage: "checkmark")
                    } else {
                        Text("\(language.flag) \(language.displayName)")
                    }
                }
            }
        } label: {
            Image(systemName: store.query.languages.isEmpty ? "globe" : "globe.badge.chevron.backward")
                .accessibilityLabel("Filtr języków")
        }
        .menuActionDismissBehavior(.disabled)
    }
}
