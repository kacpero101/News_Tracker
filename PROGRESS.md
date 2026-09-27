# PROGRESS – News Tracker

_Ostatnia aktualizacja: 2026-09-27_

## Plan (MVP + etap opcjonalny)

1. ✅ Szkielet repo: `.gitignore`, `PROGRESS.md`, `DECISIONS.md`, `README.md`.
2. ✅ `NewsCore` (Swift Package, bez UI): modele, parser RSS 2.0 / RSS 1.0 / Atom, czyszczenie HTML i daty, klasyfikator słów kluczowych, deduplikacja, filtrowanie i wyszukiwanie, równoległe pobieranie z izolacją błędów, cache JSON, lista „do przeczytania”, konfiguracja `sources.json` / `keywords.json`.
3. ✅ Testy jednostkowe na fixtures (bez sieci) – **93 testy, wszystkie przechodzą** (`swift test`, Swift 6.2.4, Linux).
4. ✅ Aplikacja iOS (SwiftUI, iOS 17) + `project.yml` (XcodeGen).
5. ✅ README z instrukcją krok po kroku.
6. ✅ Etap opcjonalny: Claude API (domyślnie wyłączone, klucz w Keychain, testy tylko na mockach).
7. ✅ Pull Request do `main`: https://github.com/kacpero101/News_Tracker/pull/1
8. ✅ Rynki: śledzenie cen akcji/ETF/krypto, reguły „zmiana ≥ X% w ciągu N h”, powiadomienia lokalne + GitHub Actions/ntfy.
9. ✅ Po testach na symulatorze: własne kategorie, „Ignoruj podobne”, przycisk „Do przeczytania” przy każdym newsie, kategorie na liście „Do przeczytania”, oznaczanie jako przeczytany + archiwum przeczytanych, archiwum alertów, wyszukiwarka instrumentów (URNU/URNX), poprawka błędnych kategorii „Finanse”.
10. ✅ Nowe źródła (money.pl, Puls Biznesu, Business Insider PL, GPW, Spider's Web, Defence24, Zaufana Trzecia Strona) – razem 33 kanały; automatyczne znajdowanie kanału na stronie WWW; „Dodaj źródło” w Ustawieniach.
11. ✅ Kategorie Obronność i Cyberbezpieczeństwo (wbudowane, PL/EN/DE), chip „Bez kategorii” (Newsy i „Do przeczytania”). **93 testy przechodzą.**

## Zrobione

- **NewsCore** (`NewsCore/`):
  - `FeedParser` – RSS 2.0, RSS 1.0 (RDF), Atom; `FoundationXML` na Linuksie; CDATA, encje HTML, linki z `guid`, `content:encoded`, fallback `updated` → data.
  - `FeedDateParser` – RFC 822 (różne warianty stref) i ISO 8601 (z/bez ułamków sekund).
  - `TopicClassifier` + `keywords.json` – PL/EN/DE + `common`, prefiksy `*`, frazy, bez diakrytyków.
  - `Deduplicator` + `URLNormalizer` – po URL (bez parametrów śledzących) i tytule; scalanie tematów i źródeł.
  - `ArticleQuery` – filtr tematów (LUB), języków, wyszukiwanie prefiksowe bez diakrytyków, sortowanie od najnowszych.
  - `FeedAggregator` – równoległe pobieranie, każde źródło niezależnie; błędy zbierane w `failures`.
  - `NewsRepository` (cache 7 dni / 1500 artykułów), `ReadingList`, `JSONFileStore`.
  - `ClaudeArticleEnhancer` – opcjonalny, surowe HTTP do Messages API, structured output (JSON Schema).
- **Aplikacja** (`NewsTrackerApp/`): zakładki Newsy / Do przeczytania / Ustawienia; chipy tematów, menu języków, `searchable`, `refreshable`, swipe „do przeczytania”, menu kontekstowe (przeglądarka, udostępnianie), `SFSafariViewController`, baner niedostępnych źródeł, włączanie/wyłączanie źródeł, ustawienia AI (Keychain, wybór modelu), czyszczenie cache.
- **`project.yml`** dla XcodeGen (iOS 17, zależność od lokalnego pakietu `NewsCore`, generowany Info.plist). Zweryfikowany w chmurze: XcodeGen zbudowany ze źródeł na Linuksie poprawnie generuje `NewsTracker.xcodeproj` (target iOS 17.0, lokalna referencja do pakietu NewsCore).

- **Rynki** (`NewsCore/Sources/NewsCore/Markets`, `Notifications`, `Sources/PriceWatch`):
  - `WatchedAsset`/`AlertRule` (okno, próg, kierunek), `PriceWatchConfiguration` (`watchlist.json` w zasobach, `alerts.json` w katalogu głównym),
  - `YahooFinanceProvider`, `CoinGeckoProvider`, `PriceService` (routing),
  - `PriceMoveDetector` + `PriceAlertEngine` (tylko nowe ruchy od poprzedniego sprawdzenia), `PriceAlertFormatter` (teksty PL),
  - `NtfyNotifier`, `PriceWatchRunner` (wspólny dla aplikacji i CLI), CLI `price-watch` (`--dry-run`, `--test`, `--state`),
  - workflow `.github/workflows/price-watch.yml` (co godzinę, cache kompilacji i stanu).
- **Aplikacja:** zakładka „Rynki” (ceny, zmiana w oknie każdej reguły, ostatnie alerty), edytor instrumentu i reguł ze sprawdzaniem symbolu, lokalne powiadomienia, `BGAppRefreshTask`, ekran „Powiadomienia o cenach” z instrukcją ntfy i eksportem `alerts.json`.

- **Nowe funkcje (runda 2):** `Topic` jako typ otwarty + `CustomCategory`, `MuteList`/`SimilarNewsSuggester`, `ReadArchive` + `DayGrouping`, `YahooSymbolSearch`. W aplikacji: `TopicCatalog`, `TopicChips` (Newsy i „Do przeczytania”), `CategoryEditorView`, `IgnoreSimilarView`/`MutedNewsView`/`CategoriesSettingsView`, `ReadArchiveView`, `PriceAlertsArchiveView`, wyszukiwarka w `AssetEditorView`.

- Runda 2 (kategorie, ignorowanie, przeczytane i archiwa, wyszukiwarka instrumentów) **zbudowana w Xcode bez błędów** (2026-09-27).
- Runda 3 (nowe źródła, „Dodaj źródło”, automatyczne znajdowanie kanału, Obronność, Cyberbezpieczeństwo, „Bez kategorii”) **zbudowana i przetestowana przez użytkownika – wszystko działa** (2026-09-27).

- **Powiadomienia o cenach przez GitHub Actions + ntfy działają** (2026-09-27): sekret `NTFY_TOPIC` ustawiony, testowe powiadomienie dotarło na telefon. Pełne sprawdzenie pobrało ceny wszystkich 9 instrumentów z `alerts.json` (Yahoo + CoinGecko działają z serwerów GitHuba). Jedno uruchomienie trwa ok. 40 s z kompilacją z cache.

## Następne (propozycje po MVP)

- Zweryfikować źródła RSS na prawdziwej sieci i ustawić `"verified": true` (lub podmienić niedziałające).
- Dostroić `keywords.json` na podstawie prawdziwych nagłówków (fałszywe trafienia / braki).
- Ikona aplikacji (obecnie pusty `AppIcon`).
- Testy UI / snapshoty w Xcode; ewentualnie target testów aplikacji dla `NewsStore`.
- Odświeżanie w tle (`BGAppRefreshTask`) – poza zakresem MVP.
- Import/edycja własnych źródeł w aplikacji.

## Znane problemy

- **API cen niedostępne z chmury** (proxy blokuje Yahoo i CoinGecko): dostawcy przetestowani na zapisanych odpowiedziach. Do sprawdzenia na prawdziwej sieci (patrz niżej).
- Yahoo Finance to nieoficjalne API: może zmienić format lub ograniczać zapytania. W razie problemów można przełączyć krypto na CoinGecko, a dla akcji dopisać innego dostawcę (`PriceHistoryProvider`).
- Sprawdzanie w tle na iOS jest nieregularne (decyduje system). Do niezawodnych alertów służy GitHub Actions + ntfy.

- ~~Kod aplikacji SwiftUI nie był kompilowany w chmurze~~: **zbudowany i uruchomiony w Xcode na symulatorze iPhone 17** po jednej poprawce (`NewsStore.init`). Newsy się ładują.
- **Źródła RSS:** 25 z 26 kanałów działało w aplikacji na symulatorze (2026-09-27) i ma `verified: true`. Rzeczpospolita – Ekonomia zwracała 404; adres zmieniono na `https://www.rp.pl/rss/451-ekonomia` (znaleziony w wyszukiwarce, niezweryfikowany, `verified: false`).
- Klasyfikacja słowami kluczowymi jest heurystyczna – możliwe fałszywe trafienia (np. „bank” w kontekście innym niż finanse).
- Atom `content type="xhtml"` (treść jako elementy XML) nie jest wczytywany jako opis – rzadki przypadek; używany jest wtedy `summary`.

## Do zrobienia lokalnie (na Macu)

1. **Przejrzyj i scal PR** https://github.com/kacpero101/News_Tracker/pull/1 (po sprawdzeniu poniższych punktów).
2. **Zbuduj aplikację:**
   ```bash
   brew install xcodegen
   xcodegen            # w katalogu głównym repo
   open NewsTracker.xcodeproj
   ```
   Ustaw Team w Signing & Capabilities, uruchom na symulatorze iOS 17+ (⌘R). Zgłoś/popraw ewentualne błędy kompilacji w `NewsTrackerApp/`.
3. **Uruchom testy logiki:** `cd NewsCore && swift test` (lub ⌘U po otwarciu `NewsCore/Package.swift`).
4. **Zweryfikuj źródła RSS** – dla każdego URL z `NewsCore/Sources/NewsCore/Resources/sources.json`:
   ```bash
   cd NewsCore/Sources/NewsCore/Resources
   python3 -c "import json;[print(s['id'],s['url']) for s in json.load(open('sources.json'))['sources']]" | \
   while read id url; do
     code=$(curl -s -o /tmp/feed.xml -w '%{http_code}' -L -A 'NewsTracker/1.0' "$url")
     head -c 300 /tmp/feed.xml | grep -qE '<rss|<feed|<rdf:RDF' && ok=feed || ok=NOT-FEED
     echo "$code $ok $id"
   done
   ```
   Działające oznacz `"verified": true`; niedziałające popraw lub usuń. W aplikacji niedziałające źródła są też widoczne w banerze „Niedostępne źródła” i w Ustawienia → Kanały RSS.
5. **Sprawdź na urządzeniu/symulatorze:** pull-to-refresh, filtry tematów i języków, wyszukiwanie (np. „inflacja”, „bitcoin”), swipe „Do przeczytania”, otwieranie artykułu w Safari, wyłączenie źródła w Ustawieniach.
6. (Opcjonalnie) **AI:** wpisz własny klucz API Anthropic w Ustawienia → AI, włącz przełącznik, odśwież listę – przy artykułach pojawi się streszczenie z ikoną ✨. Pamiętaj, że wywołania są płatne; w tej sesji nie wykonano żadnego prawdziwego wywołania API.
7. **Nowe źródła:** po odświeżeniu sprawdź baner „Niedostępne źródła” i Ustawienia → Kanały RSS (przy GPW, money.pl i Pulsie Biznesu może być widoczne „Kanał znaleziony na stronie: …”). Działające oznacz w `sources.json` jako `verified: true` albo daj znać, które nie działają.
8. **Po `git pull` uruchom `xcodegen`** (doszły nowe pliki widoków) i sprawdź nowe funkcje: chip „+ Dodaj” (własna kategoria), przytrzymanie newsa → „Ignoruj podobne…”, zakładka przy każdym newsie, zielony ✓ i archiwum na liście „Do przeczytania”, Rynki → Archiwum alertów, wyszukiwarka „URNU” w edytorze instrumentu.
9. **Rynki:** w zakładce Rynki pociągnij listę w dół. Przy każdym instrumencie powinna pojawić się cena. Dodaj własny instrument i użyj „Sprawdź symbol”. Włącz powiadomienia i wyślij testowe (Ustawienia → Powiadomienia o cenach). Sprawdzanie w tle przetestujesz w Xcode: zatrzymaj aplikację debuggerem i w konsoli LLDB wpisz
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.example.newstracker.pricecheck"]`.
10. ~~**Powiadomienia bez aplikacji**~~ – zrobione (PR #2, test OK). Zmiana listy instrumentów: wyeksportuj `alerts.json` z aplikacji i podmień plik w repo. Dawne kroki: zainstaluj ntfy na iPhonie i zasubskrybuj losowy temat, dodaj sekret `NTFY_TOPIC` w GitHub (Settings → Secrets and variables → Actions), potem Actions → Price watch → Run workflow z opcją testu. Szczegóły w README („Rynki”).
11. (Opcjonalnie) Dodaj ikonę aplikacji 1024×1024 w `NewsTrackerApp/Resources/Assets.xcassets/AppIcon.appiconset`.

## Informacje dla kolejnej sesji

- Toolchain Swift w chmurze: `download.swift.org` jest zablokowany; działa rozpakowanie obrazu Docker `swift:6.2.4-noble` z Docker Hub (warstwy przez API rejestru) do `/opt/swiftroot`, potem `export PATH=/opt/swiftroot/usr/bin:$PATH`.
- Branch roboczy: `claude/keen-goodall-cj91f0`.
