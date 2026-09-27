import NewsCore
import SwiftUI

/// Headline, short description, source, date and topics of one article,
/// with a "read later" button (and optionally a "mark as read" button) in the top-right corner.
struct ArticleRow: View {
    let article: Article
    let isSaved: Bool
    let onToggleSaved: () -> Void
    /// Dims the headline of news already marked as read.
    var isRead = false
    /// Shows a "mark as read" button (reading list).
    var onMarkRead: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(article.language.flag)
                Text(article.sourceName)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text("·")
                if let date = article.publishedAt {
                    Text(date, style: .relative)
                } else {
                    Text("brak daty")
                }
                if isRead {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .accessibilityLabel("Przeczytane")
                }
                Spacer(minLength: 0)
                if let onMarkRead {
                    Button(action: onMarkRead) {
                        Image(systemName: "checkmark.circle")
                            .font(.body)
                            .foregroundStyle(Color.green)
                            .frame(width: 36, height: 28, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Oznacz jako przeczytany")
                }
                Button(action: onToggleSaved) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.body)
                        .foregroundStyle(isSaved ? Color.accentColor : Color.secondary)
                        .frame(width: 36, height: 28, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isSaved ? "Usuń z listy do przeczytania" : "Zapisz do przeczytania")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(article.title)
                .font(.headline)
                .foregroundStyle(isRead ? Color.secondary : Color.primary)
                .multilineTextAlignment(.leading)

            if let aiSummary = article.aiSummary {
                Label(aiSummary, systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            } else if !article.summary.isEmpty {
                Text(article.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if !article.topics.isEmpty || !article.additionalSourceNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(article.topics.sorted(), id: \.self) { topic in
                        TopicBadge(topic: topic)
                    }
                    if !article.additionalSourceNames.isEmpty {
                        Text("+ \(article.additionalSourceNames.count) źr.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Także w: \(article.additionalSourceNames.joined(separator: ", "))")
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct TopicBadge: View {
    let topic: Topic

    var body: some View {
        Label(topic.displayName, systemImage: topic.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(topic.color.opacity(0.15), in: Capsule())
            .foregroundStyle(topic.color)
    }
}
