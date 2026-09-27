import Foundation
import NewsCore
import Observation

/// App-wide state: articles, filters, reading list, settings.
/// A thin layer over `NewsCore`; all feed logic lives in the package.
@MainActor
@Observable
final class NewsStore {
    // MARK: Articles & filters

    private(set) var articles: [Article] = []
    var query = ArticleQuery()
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var failures: [SourceFailure] = []
    private(set) var configurationError: String?
    /// One-off error shown in an alert.
    var errorMessage: String?

    var filteredArticles: [Article] { query.apply(to: articles) }

    // MARK: Reading list

    private(set) var readingList: [Article] = []
    private(set) var savedIDs: Set<String> = []

    // MARK: Sources

    let sources: [FeedSource]
    var disabledSourceIDs: Set<String> {
        didSet { defaults.set(Array(disabledSourceIDs), forKey: Keys.disabledSources) }
    }
    var enabledSources: [FeedSource] { sources.filter { !disabledSourceIDs.contains($0.id) } }

    // MARK: Optional AI (off by default)

    var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: Keys.aiEnabled) }
    }
    var aiModel: String {
        didSet { defaults.set(aiModel, forKey: Keys.aiModel) }
    }
    private(set) var hasAPIKey: Bool
    private(set) var aiStatus: String?
    private(set) var isEnhancing = false

    // MARK: Dependencies

    private let repository: NewsRepository
    private let readingListStore: ReadingList
    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private var enhanceTask: Task<Void, Never>?

    /// Automatic refresh on launch only if the cache is older than this.
    private let staleInterval: TimeInterval = 15 * 60

    private enum Keys {
        static let disabledSources = "disabledSourceIDs"
        static let aiEnabled = "aiEnabled"
        static let aiModel = "aiModel"
        static let lastRefresh = "lastRefresh"
    }

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = .claudeAPIKey) {
        self.defaults = defaults
        self.keychain = keychain

        let configuration: (sources: [FeedSource], keywords: KeywordList, error: String?)
        do {
            configuration = (try NewsConfiguration.defaultSources(), try NewsConfiguration.defaultKeywords(), nil)
        } catch {
            configuration = ([], KeywordList(topics: [:]), "Nie udało się wczytać konfiguracji: \(error.localizedDescription)")
        }
        let keywords = configuration.keywords
        self.sources = configuration.sources
        self.configurationError = configuration.error

        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ))?.appendingPathComponent("NewsTracker", isDirectory: true)

        repository = NewsRepository(
            aggregator: FeedAggregator(classifier: TopicClassifier(keywords: keywords)),
            cache: directory.map { JSONFileStore(fileURL: $0.appendingPathComponent("articles.json")) }
        )
        readingListStore = ReadingList(
            store: directory.map { JSONFileStore(fileURL: $0.appendingPathComponent("reading-list.json")) }
        )

        disabledSourceIDs = Set(defaults.stringArray(forKey: Keys.disabledSources) ?? [])
        aiEnabled = defaults.bool(forKey: Keys.aiEnabled)
        aiModel = defaults.string(forKey: Keys.aiModel) ?? ClaudeArticleEnhancer.defaultModel
        lastRefresh = defaults.object(forKey: Keys.lastRefresh) as? Date
        hasAPIKey = keychain.read() != nil
    }

    // MARK: Lifecycle

    func start() async {
        articles = await repository.cachedArticles()
        await reloadReadingList()
        let isStale = lastRefresh.map { Date().timeIntervalSince($0) > staleInterval } ?? true
        if articles.isEmpty || isStale {
            await refresh()
        }
    }

    /// Fetches all enabled sources. Broken sources are reported in `failures`
    /// and never prevent other articles from being shown.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let outcome = await repository.refresh(sources: enabledSources)
        articles = outcome.articles
        failures = outcome.failures
        lastRefresh = Date()
        defaults.set(lastRefresh, forKey: Keys.lastRefresh)

        if aiEnabled && hasAPIKey {
            enhanceInBackground()
        }
    }

    func clearCache() async {
        await repository.clearCache()
        articles = []
        lastRefresh = nil
        defaults.removeObject(forKey: Keys.lastRefresh)
    }

    // MARK: Filters

    func toggleTopic(_ topic: Topic) {
        if query.topics.contains(topic) {
            query.topics.remove(topic)
        } else {
            query.topics.insert(topic)
        }
    }

    func toggleLanguage(_ language: Language) {
        if query.languages.contains(language) {
            query.languages.remove(language)
        } else {
            query.languages.insert(language)
        }
    }

    func clearFilters() {
        query.topics = []
        query.languages = []
    }

    // MARK: Reading list

    func isSaved(_ article: Article) -> Bool {
        savedIDs.contains(article.id)
    }

    func toggleSaved(_ article: Article) async {
        do {
            try await readingListStore.toggle(article)
        } catch {
            errorMessage = "Nie udało się zapisać listy: \(error.localizedDescription)"
        }
        await reloadReadingList()
    }

    private func reloadReadingList() async {
        readingList = await readingListStore.all
        savedIDs = Set(readingList.map(\.id))
    }

    // MARK: Sources

    func isEnabled(_ source: FeedSource) -> Bool {
        !disabledSourceIDs.contains(source.id)
    }

    func setEnabled(_ enabled: Bool, for source: FeedSource) {
        if enabled {
            disabledSourceIDs.remove(source.id)
        } else {
            disabledSourceIDs.insert(source.id)
        }
    }

    func failure(for source: FeedSource) -> SourceFailure? {
        failures.first { $0.sourceID == source.id }
    }

    // MARK: AI (optional)

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try keychain.save(trimmed)
            hasAPIKey = true
            aiStatus = "Klucz zapisany w pęku kluczy (Keychain)."
        } catch {
            aiStatus = "Nie udało się zapisać klucza: \(error.localizedDescription)"
        }
    }

    func deleteAPIKey() {
        do {
            try keychain.delete()
            hasAPIKey = false
            aiEnabled = false
            aiStatus = "Klucz usunięty."
        } catch {
            aiStatus = "Nie udało się usunąć klucza: \(error.localizedDescription)"
        }
    }

    /// Enhances the newest visible articles (at most 10 per run) with AI topics and summaries.
    func enhanceInBackground() {
        guard aiEnabled, !isEnhancing, let apiKey = keychain.read() else { return }
        let candidates = filteredArticles
        let enhancer = ClaudeArticleEnhancer(model: aiModel)
        isEnhancing = true
        aiStatus = "Analiza AI w toku…"

        enhanceTask = Task { [weak self] in
            do {
                let updated = try await enhancer.enhance(candidates, apiKey: apiKey, limit: 10)
                guard let self else { return }
                await self.repository.update(updated)
                self.articles = await self.repository.cachedArticles()
                self.aiStatus = "AI: zaktualizowano \(updated.count) artykułów."
            } catch {
                self?.aiStatus = "AI: \(error.localizedDescription)"
            }
            self?.isEnhancing = false
        }
    }
}
