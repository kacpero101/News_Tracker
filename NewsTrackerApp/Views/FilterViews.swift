import NewsCore
import SwiftUI

/// Horizontally scrolling category chips (multi-select; none selected = all categories).
/// Used by the news list and the reading list.
struct TopicChips: View {
    @Environment(NewsStore.self) private var store
    @Binding var selection: Set<Topic>
    /// Shows a "+" chip that starts creating a custom category.
    var onAddCategory: (() -> Void)?
    /// Context-menu actions for custom categories.
    var onEditCategory: ((CustomCategory) -> Void)?
    var onDeleteCategory: ((CustomCategory) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Wszystkie", systemImage: "square.grid.2x2", color: .accentColor, isOn: selection.isEmpty) {
                    selection = []
                }
                ForEach(store.allTopics, id: \.self) { topic in
                    let topicChip = chip(title: topic.displayName, systemImage: topic.systemImage, color: topic.color, isOn: selection.contains(topic)) {
                        if selection.contains(topic) {
                            selection.remove(topic)
                        } else {
                            selection.insert(topic)
                        }
                    }
                    if let category = store.category(for: topic), onEditCategory != nil || onDeleteCategory != nil {
                        // Long press on a custom category: edit / delete.
                        topicChip.contextMenu {
                            if let onEditCategory {
                                Button {
                                    onEditCategory(category)
                                } label: {
                                    Label("Edytuj kategorię", systemImage: "pencil")
                                }
                            }
                            if let onDeleteCategory {
                                Button(role: .destructive) {
                                    onDeleteCategory(category)
                                } label: {
                                    Label("Usuń kategorię", systemImage: "trash")
                                }
                            }
                        }
                    } else {
                        topicChip
                    }
                }
                if let onAddCategory {
                    Button(action: onAddCategory) {
                        Label("Dodaj", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dodaj kategorię")
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
