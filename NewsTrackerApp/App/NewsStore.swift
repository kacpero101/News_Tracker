import Foundation
import NewsCore
import Observation

/// App-wide state: articles, filters, reading list, settings.
/// A thin layer over `NewsCore`; all feed logic lives in the package.
@MainActor
@Observable
final class NewsStore {
    // MARK: Articles & filters

    private(set) var articles: [Article] = [] {
        didSet { updateVisibleArticles() }
    }
    /// `articles` without muted ("ignored") news.
    private(set) var visibleArticles: [Article] = []
    var query = ArticleQuery()
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var failures: [SourceFailure] = []
    private(set) var configurationError: String?
    /// One-off error shown in an alert.
    var errorMessage: String?

    var filteredArticles: [Article] { query.apply(to: visibleArticles) }

    /// Number of news hidden by the mute list.
    var hiddenCount: Int { articles.count - visibleArticles.count }

    // MARK: Reading list

    private(set) var readingList: [Article] = []
    private(set) var savedIDs: Set<String> = []
    /// Archive of news marked as read (newest first).
    private(set) var readArchive: [ReadArticle] = []
    private(set) var readIDs: Set<String> = []
    /// Category filter of the reading list (empty = all).
    var readingListTopics: Set<Topic> = []

    var filteredReadingList: [Article] {
        readingListTopics.isEmpty ? readingList : readingList.filter { !$0.topics.isDisjoint(with: readingListTopics) }
    }

    // MARK: Categories

    /// User-defined categories (shown after the built-in ones).
    private(set) var customCategories: [CustomCategory]
    var allTopics: [Topic] { Topic.builtIn + customCategories.map(\.topic) }

    // MARK: Ignored news

    private(set) var muteList: MuteList
    private var muteMatcher: MuteMatcher

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
    private let readArchiveStore: ReadArchive
    private let baseKeywords: KeywordList
    private let categoriesStore: JSONFileStore<[CustomCategory]>?
    private let muteStore: JSONFileStore<MuteList>?
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
        baseKeywords = configuration.keywords
        self.sources = configuration.sources
        self.configurationError = configuration.error

        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ))?.appendingPathComponent("NewsTracker", isDirectory: true)

        let categoriesFile: JSONFileStore<[CustomCategory]>? = directory.map { JSONFileStore(fileURL: $0.appendingPathComponent("categories.json")) }
        let muteFile: JSONFileStore<MuteList>? = directory.map { JSONFileStore(fileURL: $0.appendingPathComponent("mute-list.json")) }
        categoriesStore = categoriesFile
        muteStore = muteFile
        let categories = ((try? categoriesFile?.load()) ?? nil) ?? []
        let mutes = ((try? muteFile?.load()) ?? nil) ?? MuteList()
        TopicCatalog.shared.update(categories)

        repository = NewsRepository(
            aggregator: FeedAggregator(classifier: TopicClassifier(keywords: configuration.keywords.merging(categories))),
            cache: directory.map { JSONFileStore(fileURL: $0.appendingPathComponent("articles.json")) }
        )
        readingListStore = ReadingList(
            store: directory.map { JSONFileStore(fileURL: $0.appendingPathComponent("reading-list.json")) }
        )
        readArchiveStore = ReadArchive(
            store: directory.map { JSONFileStore(fileURL: $0.appendingPathComponent("read-archive.json")) }
        )

        customCategories = categories
        muteList = mutes
        muteMatcher = mutes.matcher()
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
        await reloadReadArchive()
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

    // MARK: Categories

    func category(for topic: Topic) -> CustomCategory? {
        customCategories.first { $0.topic == topic }
    }

    /// Adds or updates a custom category and re-classifies downloaded and saved news.
    func saveCategory(_ category: CustomCategory) async {
        let previous = customCategories
        if let index = customCategories.firstIndex(where: { $0.id == category.id }) {
            customCategories[index] = category
        } else {
            customCategories.append(category)
        }
        await applyCategories(previous: previous)
    }

    func deleteCategory(_ category: CustomCategory) async {
        let previous = customCategories
        customCategories.removeAll { $0.id == category.id }
        await applyCategories(previous: previous)
    }

    private func applyCategories(previous: [CustomCategory]) async {
        TopicCatalog.shared.update(customCategories)
        do {
            try categoriesStore?.save(customCategories)
        } catch {
            errorMessage = "Nie udało się zapisać kategorii: \(error.localizedDescription)"
        }
        let classifier = TopicClassifier(keywords: baseKeywords.merging(customCategories))
        let managed = Set((previous + customCategories).map(\.topic))
        articles = await repository.applyClassifier(classifier, managing: managed)
        try? await readingListStore.reclassify(with: classifier, managing: managed)
        try? await readArchiveStore.reclassify(with: classifier, managing: managed)
        await reloadReadingList()
        await reloadReadArchive()

        // Forget filter selections of deleted categories.
        let valid = Set(allTopics)
        query.topics.formIntersection(valid)
        readingListTopics.formIntersection(valid)
    }

    // MARK: Ignored news

    /// Hides news containing any of `keywords` (and optionally one specific article).
    func mute(keywords: [String], hiding article: Article?) {
        var updated = muteList
        updated.add(keywords: keywords)
        if let article {
            updated.hiddenArticleIDs.insert(article.id)
        }
        setMuteList(updated)
    }

    func hide(_ article: Article) {
        var updated = muteList
        updated.hiddenArticleIDs.insert(article.id)
        setMuteList(updated)
    }

    func unmute(keyword: String) {
        var updated = muteList
        updated.remove(keyword: keyword)
        setMuteList(updated)
    }

    func restoreHiddenArticles() {
        var updated = muteList
        updated.hiddenArticleIDs = []
        setMuteList(updated)
    }

    /// Which muted keywords hide this article (for the settings screen).
    func mutedKeywords(in article: Article) -> [String] {
        muteMatcher.matchingKeywords(article)
    }

    private func setMuteList(_ list: MuteList) {
        muteList = list
        muteMatcher = list.matcher()
        updateVisibleArticles()
        do {
            try muteStore?.save(list)
        } catch {
            errorMessage = "Nie udało się zapisać listy ignorowanych: \(error.localizedDescription)"
        }
    }

    private func updateVisibleArticles() {
        visibleArticles = muteMatcher.visible(articles)
    }

    // MARK: Reading list

    func isSaved(_ article: Article) -> Bool {
        savedIDs.contains(article.id)
    }

    func toggleSaved(_ article: Article) async {
        do {
            let nowSaved = try await readingListStore.toggle(article)
            // Saving an already read article puts it back on the reading list.
            if nowSaved && readIDs.contains(article.id) {
                try await readArchiveStore.remove(ids: [article.id])
            }
        } catch {
            errorMessage = "Nie udało się zapisać listy: \(error.localizedDescription)"
        }
        await reloadReadingList()
        await reloadReadArchive()
    }

    // MARK: Read archive

    func isRead(_ article: Article) -> Bool {
        readIDs.contains(article.id)
    }

    /// Moves the article to the archive of read news (and off the reading list).
    func markRead(_ article: Article) async {
        do {
            try await readArchiveStore.markRead(article)
            if savedIDs.contains(article.id) {
                try await readingListStore.remove(id: article.id)
            }
        } catch {
            errorMessage = "Nie udało się oznaczyć jako przeczytany: \(error.localizedDescription)"
        }
        await reloadReadingList()
        await reloadReadArchive()
    }

    /// Removes the "read" mark without adding the article back to the reading list.
    func markUnread(_ article: Article) async {
        await deleteFromArchive(ids: [article.id])
    }

    /// Moves an archived article back to the reading list.
    func restoreToReadingList(_ entry: ReadArticle) async {
        do {
            try await readArchiveStore.remove(ids: [entry.id])
            try await readingListStore.add(entry.article)
        } catch {
            errorMessage = "Nie udało się przywrócić: \(error.localizedDescription)"
        }
        await reloadReadingList()
        await reloadReadArchive()
    }

    func deleteFromArchive(ids: Set<String>) async {
        do {
            try await readArchiveStore.remove(ids: ids)
        } catch {
            errorMessage = "Nie udało się usunąć z archiwum: \(error.localizedDescription)"
        }
        await reloadReadArchive()
    }

    func clearReadArchive() async {
        do {
            try await readArchiveStore.clear()
        } catch {
            errorMessage = "Nie udało się wyczyścić archiwum: \(error.localizedDescription)"
        }
        await reloadReadArchive()
    }

    private func reloadReadArchive() async {
        readArchive = await readArchiveStore.all
        readIDs = Set(readArchive.map(\.id))
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
