import NewsCore
import Observation

/// Registry of user-defined categories, so any view can show a topic's name, icon and color.
/// Observable: views re-render when a category is renamed or recolored.
@Observable
final class TopicCatalog {
    static let shared = TopicCatalog()

    private(set) var customCategories: [CustomCategory] = []

    func update(_ categories: [CustomCategory]) {
        customCategories = categories
    }

    func category(for topic: Topic) -> CustomCategory? {
        customCategories.first { $0.topic == topic }
    }
}
