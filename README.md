# News Tracker

Natywna aplikacja iOS (Swift/SwiftUI), która zbiera newsy z darmowych kanałów RSS/Atom (PL/EN/DE) i porządkuje je tematycznie: **finanse, polityka, przełomowe odkrycia, kryptowaluty, gospodarka**.

- tylko darmowe RSS/Atom, bez kluczy API i bez backendu,
- klasyfikacja offline: kategoria źródła + słowa kluczowe (PL/EN/DE),
- deduplikacja tego samego artykułu z wielu kanałów,
- lista najnowszych newsów, filtry tematów i języków, wyszukiwarka, pull-to-refresh,
- lista „Do przeczytania”, oryginał otwierany w `SFSafariViewController`,
- opcjonalnie (domyślnie wyłączone): klasyfikacja i streszczenia przez Claude API z kluczem w Keychain.

## Struktura repozytorium

```
News_Tracker/
├── project.yml              # definicja projektu dla XcodeGen
├── NewsCore/                # Swift Package – cała logika (bez UI), testowana na Linuksie
│   ├── Package.swift
│   ├── Sources/NewsCore/
│   │   ├── Models/          # Article, Topic, Language, FeedSource
│   │   ├── Parsing/         # FeedParser (RSS 2.0/1.0, Atom), daty, HTML, normalizacja tekstu
│   │   ├── Classification/  # KeywordList, TopicClassifier
│   │   ├── Deduplication/   # URLNormalizer, Deduplicator
│   │   ├── Filtering/       # ArticleQuery (filtry + wyszukiwanie)
│   │   ├── Networking/      # HTTPClient, FeedAggregator
│   │   ├── Persistence/     # JSONFileStore, NewsRepository (cache), ReadingList
│   │   ├── Config/          # wczytywanie sources.json / keywords.json
│   │   ├── AI/              # ClaudeArticleEnhancer (opcjonalny)
│   │   └── Resources/       # sources.json, keywords.json
│   └── Tests/NewsCoreTests/ # testy + Fixtures/ (przykładowe RSS/Atom)
├── NewsTrackerApp/          # aplikacja SwiftUI (cienka warstwa UI)
│   ├── App/                 # NewsTrackerApp, NewsStore (stan aplikacji)
│   ├── Views/               # lista, wiersz, filtry, do przeczytania, ustawienia
│   ├── Support/             # SafariView, KeychainStore, nazwy wyświetlane
│   └── Resources/           # Assets.xcassets
├── PROGRESS.md              # postęp, znane problemy, kroki do wykonania lokalnie
└── DECISIONS.md             # decyzje projektowe z uzasadnieniem
```

## Uruchomienie na Macu – krok po kroku

Wymagania: macOS z **Xcode 15 lub nowszym** (iOS 17 SDK), [Homebrew](https://brew.sh).

1. Sklonuj repozytorium i przejdź do katalogu:
   ```bash
   git clone https://github.com/kacpero101/News_Tracker.git
   cd News_Tracker
   ```
2. Zainstaluj XcodeGen:
   ```bash
   brew install xcodegen
   ```
3. Wygeneruj projekt Xcode (w katalogu głównym repo, tam gdzie `project.yml`):
   ```bash
   xcodegen
   ```
   Powstanie `NewsTracker.xcodeproj` (jest w `.gitignore` – po każdej zmianie struktury plików uruchom `xcodegen` ponownie).
4. Otwórz projekt:
   ```bash
   open NewsTracker.xcodeproj
   ```
5. W Xcode: target **NewsTracker** → **Signing & Capabilities** → wybierz swój **Team** (dla symulatora wystarczy „Sign to Run Locally” / Personal Team). W razie konfliktu zmień `PRODUCT_BUNDLE_IDENTIFIER` (np. w `project.yml`, potem `xcodegen`).
6. Wybierz symulator (np. iPhone 15, iOS 17+) i uruchom: **⌘R**.
7. Po starcie aplikacja pobiera newsy automatycznie; później odświeżasz gestem pull-to-refresh.

### Testy logiki (`NewsCore`)

Na Macu lub Linuksie (Swift 5.9+):
```bash
cd NewsCore
swift build
swift test
```
Można też otworzyć `NewsCore/Package.swift` w Xcode i uruchomić testy (**⌘U**). Testy nie korzystają z sieci (fixtures w `Tests/NewsCoreTests/Fixtures`).

## Konfiguracja

### Źródła – `NewsCore/Sources/NewsCore/Resources/sources.json`

```json
{ "id": "bbc-business", "name": "BBC News – Business",
  "url": "https://feeds.bbci.co.uk/news/business/rss.xml",
  "language": "en", "defaultCategory": "economy", "verified": false }
```
- `language`: `pl` | `en` | `de`
- `defaultCategory`: `finance` | `politics` | `breakthroughs` | `crypto` | `economy` | `null` (źródło ogólne)
- `verified`: czy adres został sprawdzony (informacyjnie; w UI niezweryfikowane mają ikonę „?”)

Źródła można też włączać/wyłączać w aplikacji: **Ustawienia → Kanały RSS**.

### Słowa kluczowe – `NewsCore/Sources/NewsCore/Resources/keywords.json`

```json
"crypto": { "common": ["bitcoin*"], "pl": ["kryptowalut*"], "en": ["cryptocurrenc*"], "de": ["kryptowahrung*"] }
```
- wielkość liter i polskie/niemieckie znaki są ignorowane (`złoty` = `zloty`, `Börse` = `borse`),
- `słowo` – całe słowo, `słowo*` – prefiks (odmiana: `kryptowalut*` → kryptowaluty, kryptowalutach),
- frazy: `"central bank"`, `"stop* procentow*"`,
- `common` – dla wszystkich języków; `minimumMatches` – ile trafień potrzeba do przypisania tematu.

Po zmianie plików JSON uruchom `swift test` – test `ConfigurationTests` sprawdza ich poprawność.

## AI (opcjonalnie)

Domyślnie wyłączone; aplikacja działa w pełni bez tego. Aby włączyć: **Ustawienia → AI** → wklej klucz API Anthropic → „Zapisz klucz” → włącz przełącznik. Klucz trafia wyłącznie do pęku kluczy (Keychain) urządzenia. Do API wysyłany jest tylko nagłówek i krótki opis z RSS, maks. 10 artykułów na odświeżenie. **Wywołania są płatne** (Twoje konto Anthropic); w Ustawieniach można wybrać tańszy model.

## Dokumentacja projektu

- [`PROGRESS.md`](PROGRESS.md) – stan prac, znane problemy, **kroki do wykonania lokalnie**,
- [`DECISIONS.md`](DECISIONS.md) – decyzje projektowe.
