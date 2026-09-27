# PROGRESS – News Tracker

_Ostatnia aktualizacja: 2026-09-27_

## Plan (MVP + etap opcjonalny)

1. ✅ Szkielet repo: `.gitignore`, `PROGRESS.md`, `DECISIONS.md`, `README.md`.
2. ✅ `NewsCore` (Swift Package, bez UI): modele, parser RSS 2.0 / RSS 1.0 / Atom, czyszczenie HTML i daty, klasyfikator słów kluczowych, deduplikacja, filtrowanie i wyszukiwanie, równoległe pobieranie z izolacją błędów, cache JSON, lista „do przeczytania”, konfiguracja `sources.json` / `keywords.json`.
3. ✅ Testy jednostkowe na fixtures (bez sieci) – **51 testów, wszystkie przechodzą** (`swift test`, Swift 6.2.4, Linux).
4. ✅ Aplikacja iOS (SwiftUI, iOS 17) + `project.yml` (XcodeGen).
5. ✅ README z instrukcją krok po kroku.
6. ✅ Etap opcjonalny: Claude API (domyślnie wyłączone, klucz w Keychain, testy tylko na mockach).
7. ⛔ Push i Pull Request do `main` – zablokowane (brak dostępu do GitHub z tej sesji, patrz „Znane problemy”).

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

## Następne (propozycje po MVP)

- Zweryfikować źródła RSS na prawdziwej sieci i ustawić `"verified": true` (lub podmienić niedziałające).
- Dostroić `keywords.json` na podstawie prawdziwych nagłówków (fałszywe trafienia / braki).
- Ikona aplikacji (obecnie pusty `AppIcon`).
- Testy UI / snapshoty w Xcode; ewentualnie target testów aplikacji dla `NewsStore`.
- Odświeżanie w tle (`BGAppRefreshTask`) – poza zakresem MVP.
- Import/edycja własnych źródeł w aplikacji.

## Znane problemy

- **Push na GitHub nie działa z tej sesji**: `git push` zwraca 403 („Claude doesn't have GitHub access to kacpero101/News_Tracker”). Dodatkowo repozytorium było puste (brak `main`), a utworzenie `main` zostało zablokowane przez uprawnienia sesji. Wszystkie commity są na lokalnym branchu `claude/keen-goodall-cj91f0`. PR nie mógł zostać otwarty.
- **Kod aplikacji SwiftUI nie był kompilowany** (brak Xcode/SDK iOS w chmurze). Pisany ostrożnie pod iOS 17, ale możliwe drobne błędy kompilacji – do sprawdzenia w Xcode.
- **Źródła RSS niezweryfikowane** – proxy chmury blokuje domeny wydawców (`verified: false` dla wszystkich). Niektóre adresy (szczególnie polskie: Rzeczpospolita, Polsat News, TVN24, Nauka w Polsce) mogą wymagać poprawki.
- Klasyfikacja słowami kluczowymi jest heurystyczna – możliwe fałszywe trafienia (np. „bank” w kontekście innym niż finanse).
- Atom `content type="xhtml"` (treść jako elementy XML) nie jest wczytywany jako opis – rzadki przypadek; używany jest wtedy `summary`.

## Do zrobienia lokalnie (na Macu)

1. **Wypchnij pracę na GitHub** (jeśli ta sesja nie zdołała):
   - połącz/odnów dostęp GitHub dla Claude (https://claude.ai/connect-github) i zainstaluj aplikację Claude GitHub na repo, albo
   - wypchnij ręcznie z kopii zawierającej te commity. Repo jest puste, więc najpierw utwórz `main` (np. pusty commit z README przez GitHub UI), potem `git push -u origin claude/keen-goodall-cj91f0` i otwórz PR do `main`.
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
7. (Opcjonalnie) Dodaj ikonę aplikacji 1024×1024 w `NewsTrackerApp/Resources/Assets.xcassets/AppIcon.appiconset`.

## Informacje dla kolejnej sesji

- Toolchain Swift w chmurze: `download.swift.org` jest zablokowany; działa rozpakowanie obrazu Docker `swift:6.2.4-noble` z Docker Hub (warstwy przez API rejestru) do `/opt/swiftroot`, potem `export PATH=/opt/swiftroot/usr/bin:$PATH`.
- Branch roboczy: `claude/keen-goodall-cj91f0`.
