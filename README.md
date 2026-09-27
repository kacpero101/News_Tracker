# News Tracker

Natywna aplikacja iOS (Swift/SwiftUI), która zbiera newsy z darmowych kanałów RSS/Atom (PL/EN/DE) i porządkuje je tematycznie: **finanse, polityka, przełomowe odkrycia, kryptowaluty, gospodarka**.

- tylko darmowe RSS/Atom, bez kluczy API i bez backendu,
- klasyfikacja offline: kategoria źródła + słowa kluczowe (PL/EN/DE),
- deduplikacja tego samego artykułu z wielu kanałów,
- lista najnowszych newsów, filtry tematów i języków, wyszukiwarka, pull-to-refresh,
- przycisk „Do przeczytania” (zakładka) przy każdym newsie, lista „Do przeczytania” z filtrem kategorii, oznaczanie jako **przeczytany** i **archiwum przeczytanych** (nie liczą się do listy „Do przeczytania”),
- **własne kategorie** (chip „+” obok wbudowanych: nazwa, słowa kluczowe, ikona, kolor),
- **„Ignoruj podobne”**: ukrywanie newsów z wybranymi słowami z nagłówka (z odmianami), pojedyncze ukrywanie newsa,
- oryginał otwierany w `SFSafariViewController`,
- opcjonalnie (domyślnie wyłączone): klasyfikacja i streszczenia przez Claude API z kluczem w Keychain,
- **Rynki**: śledzenie akcji/ETF/kryptowalut i powiadomienia o nagłych zmianach cen (np. BTC: ±8% w 48 h) – lokalnie na iPhonie oraz darmowo przez GitHub Actions + ntfy.

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
│   │   ├── Markets/         # obserwowane instrumenty, Yahoo/CoinGecko, detektor zmian cen
│   │   ├── Notifications/   # NtfyNotifier (powiadomienia push przez ntfy.sh)
│   │   └── Resources/       # sources.json, keywords.json
│   ├── Sources/PriceWatch/  # narzędzie CLI `price-watch` (uruchamiane przez GitHub Actions)
│   └── Tests/NewsCoreTests/ # testy + Fixtures/ (przykładowe RSS/Atom, odpowiedzi API cen)
├── alerts.json              # lista obserwowanych instrumentów dla GitHub Actions
├── .github/workflows/price-watch.yml  # co godzinę: sprawdzenie cen + powiadomienia ntfy
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

## Newsy: kategorie, ignorowanie, przeczytane

- **Własne kategorie:** na końcu paska kategorii jest chip **„+ Dodaj”**. Podajesz nazwę, słowa kluczowe (przecinkami; `dron*` dopasowuje odmiany; słowa działają dla wszystkich języków), ikonę i kolor. Już pobrane i zapisane newsy są od razu przypisywane. Przytrzymanie chipa własnej kategorii → edycja lub usunięcie. Lista również w Ustawienia → Kategorie.
- **Ignoruj podobne:** przytrzymaj news (albo przesuń w prawo) → „Ignoruj podobne…”. Wybierasz słowa z nagłówka (np. „przejeździe” → `przejeźdz*`) albo wpisujesz własne; newsy z tymi słowami znikają z listy. „Ukryj ten news” ukrywa pojedynczy news. Zarządzanie: Ustawienia → Ignorowane słowa.
- **Do przeczytania:** ikona zakładki przy każdym newsie. Na liście „Do przeczytania” zielony ✓ (lub przesunięcie w prawo) oznacza news jako **przeczytany**: znika z listy i trafia do **archiwum przeczytanych** (ikona archiwum w lewym górnym rogu). Z archiwum można przywrócić news do przeczytania, wyszukiwać i czyścić archiwum. Przeczytane newsy na liście Newsy mają przyciemniony tytuł i ✓.

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

**Dodawanie własnych źródeł w aplikacji:** Ustawienia → Kanały RSS → **+**. Wpisz adres serwisu (np. `pb.pl`), stronę z listą kanałów (np. `gpw.pl/_rss`) albo bezpośredni adres kanału. Aplikacja znajdzie kanały RSS/Atom (odnośniki `<link rel="alternate">`, linki „RSS” na stronie, typowe adresy `/feed`, `/rss`) i pokaże je z liczbą wpisów oraz przykładowym nagłówkiem. Własne źródła usuniesz przesunięciem w lewo.

**Adres strony zamiast kanału:** jeśli pod adresem źródła jest strona WWW, a nie kanał (np. strona z listą kanałów), aplikacja przy odświeżaniu sama wyszuka na niej kanał i zapamięta go do końca sesji. Na liście źródeł widać wtedy „Kanał znaleziony na stronie: …”.

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

## Rynki: powiadomienia o nagłych zmianach cen

Zakładka **Rynki** pokazuje obserwowane instrumenty (akcje, ETF-y, kryptowaluty), ich ostatnią cenę i zmianę w oknie każdej reguły.

**Reguła** = okno czasu + próg + kierunek, np. *BTC: w ciągu 48 h zmiana o co najmniej 8% (wzrost lub spadek)*. Instrument może mieć kilka reguł (np. 4 h / 5% i 48 h / 8%). Zmiana liczona jest od najniższej (wzrost) lub najwyższej (spadek) ceny w oknie, więc wykrywa też gwałtowny ruch w środku okna. Każdy ruch zgłaszany jest raz: dopiero gdy reguła „zaczyna” być spełniona od poprzedniego sprawdzenia.

**Dane cen (darmowe, bez kluczy):**
- **Yahoo Finance**: akcje, ETF-y, indeksy (np. `AAPL`, `SPY`, `PKN.WA`, `CDR.WA`, `SAP.DE`, `BTC-USD`). To nieoficjalny endpoint i może się zmienić.
- **CoinGecko**: kryptowaluty po ID monety (`bitcoin`, `ethereum`), waluta USD/EUR/PLN.

Dodawanie i edycja: przycisk **+** w zakładce Rynki lub dotknięcie instrumentu. **Wyszukiwarka** w edytorze (np. „uranium”, „URNU”) pokazuje symbole z giełdami. Instrumenty spoza USA mają w Yahoo sufiks giełdy (`.L` Londyn, `.DE` Xetra, `.AS`, `.MI`, `.WA`), więc sam symbol (np. `URNU`) nie wystarczy. Przycisk „Sprawdź symbol” weryfikuje dostępność danych, a przy nieznanym symbolu sam uruchamia wyszukiwanie.

Wszystkie wykryte alerty trafiają do **archiwum alertów** (Rynki → „Archiwum alertów”): pogrupowane po dniach, z filtrem instrumentu. Dotknięcie alertu otwiera notowania.

### Powiadomienia – dwa darmowe sposoby

**1. Lokalnie na iPhonie (bez konfiguracji)**
Rynki → „Włącz powiadomienia o zmianach cen”. Ceny są sprawdzane przy otwarciu aplikacji, przy odświeżeniu listy i w tle (`BGAppRefreshTask`). **Ograniczenie iOS:** to system decyduje, kiedy uruchomić sprawdzanie w tle (zwykle co kilka godzin), i nie robi tego po wymuszonym zamknięciu aplikacji.

**2. Niezawodnie: GitHub Actions + ntfy (zalecane)**
Workflow `.github/workflows/price-watch.yml` co godzinę uruchamia narzędzie `price-watch`, które sprawdza ceny z `alerts.json` i wysyła push przez [ntfy.sh](https://ntfy.sh). Działa niezależnie od telefonu i aplikacji.

1. Zainstaluj aplikację **ntfy** (App Store) i zasubskrybuj temat o długiej, losowej nazwie, np. `newstracker-7f3k9x2q`. Nazwa tematu działa jak hasło: kto ją zna, widzi powiadomienia.
2. GitHub → repozytorium → **Settings → Secrets and variables → Actions → New repository secret**: nazwa `NTFY_TOPIC`, wartość = nazwa tematu.
3. Ustaw instrumenty w `alerts.json`: ręcznie albo w aplikacji: **Ustawienia → Powiadomienia o cenach → Kopiuj alerts.json**, potem wklej do pliku i zrób commit do `main`.
4. Test: **Actions → Price watch → Run workflow**, zaznacz „Send a test notification only”.

Workflow działa tylko z domyślnego brancha (`main`), czyli po scaleniu PR. Koszt: darmowe w ramach limitu GitHub Actions (repo publiczne bez limitu; prywatne 2000 min/mies., a sprawdzanie co godzinę mieści się w nim dzięki cache kompilacji). Po wyczerpaniu limitu workflow się zatrzymuje, nie nalicza opłat, jeśli nie ustawiono płatnego limitu wydatków. Uruchomienia z harmonogramu GitHub bywają opóźnione o kilka–kilkanaście minut.

Lokalnie (Mac/Linux) można uruchomić:
```bash
cd NewsCore && swift build --product price-watch
NTFY_TOPIC=twoj-temat .build/debug/price-watch --config ../alerts.json          # sprawdzenie + powiadomienia
.build/debug/price-watch --config ../alerts.json --dry-run                      # tylko wypisz
NTFY_TOPIC=twoj-temat .build/debug/price-watch --test                          # testowe powiadomienie
```

## Dokumentacja projektu

- [`PROGRESS.md`](PROGRESS.md) – stan prac, znane problemy, **kroki do wykonania lokalnie**,
- [`DECISIONS.md`](DECISIONS.md) – decyzje projektowe.
