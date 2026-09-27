# DECISIONS – decyzje projektowe

Każda decyzja: **co** + **dlaczego**. Nowe decyzje dopisuj na końcu.

## Architektura i platforma

1. **Minimalna wersja iOS: 17.0.**
   Pozwala użyć `@Observable` (framework Observation), `ContentUnavailableView`, nowego API `searchable`/`refreshable` bez obejść. iOS 17+ to zdecydowana większość aktywnych urządzeń.

2. **Podział: `NewsCore` (Swift Package) + cienka aplikacja SwiftUI.**
   Cała logika (parsowanie, klasyfikacja, deduplikacja, filtrowanie, pobieranie, cache, integracja AI) jest w `NewsCore`, bez SwiftUI/UIKit, więc kompiluje się i jest testowana na Linuksie (`swift build`, `swift test`). Aplikacja zawiera tylko widoki, Keychain i `SFSafariViewController`.

3. **`swift-tools-version: 5.9`, tryb języka Swift 5.**
   Kompatybilność z Xcode 15+ i uniknięcie błędów ścisłej współbieżności Swift 6 w kodzie UI, którego nie da się skompilować w chmurze. Typy publiczne są mimo to `Sendable`, a stan współdzielony trzymają aktory (`NewsRepository`, `ReadingList`). Projekt aplikacji ma `SWIFT_VERSION = 5.0`.

4. **Projekt Xcode generowany przez XcodeGen (`project.yml` w katalogu głównym).**
   `*.xcodeproj` jest w `.gitignore`. `Info.plist` generowany przez Xcode (`GENERATE_INFOPLIST_FILE`), więc nie ma go w repo. `DEVELOPMENT_TEAM` pusty – ustawiasz lokalnie.

5. **Parsowanie XML: `XMLParser` z warunkowym `import FoundationXML`.**
   Bez zewnętrznych zależności (np. FeedKit). Obsługiwane formaty: RSS 2.0, RSS 1.0 (RDF), Atom 1.0. Przetwarzanie przestrzeni nazw wyłączone – elementy rozpoznawane po nazwach kwalifikowanych (`dc:date`, `content:encoded`). Błąd XML pod koniec dokumentu jest tolerowany, jeśli udało się już odczytać wpisy.

6. **Sieć: `URLSession` za protokołem `HTTPClient`.**
   Umożliwia mocki w testach (testy nie korzystają z sieci). Użyto `dataTask` + continuation zamiast `async data(for:)`, bo wersja async nie jest dostępna we wszystkich wersjach Foundation na Linuksie.

## Dane i funkcje

7. **Lokalny zapis: pliki JSON (Application Support), nie SwiftData.**
   Prosty cache (`articles.json`) i lista „do przeczytania” (`reading-list.json`) przez `JSONFileStore`. Działa i jest testowalny na Linuksie; SwiftData wymagałby przeniesienia modelu do aplikacji. Cache: artykuły z ostatnich 7 dni, maks. 1500. Uszkodzony cache = pusty cache (bez awarii).

8. **Lista „do przeczytania” przechowuje pełne kopie artykułów** (nie tylko ID), żeby zapisane pozycje nie znikały po wypadnięciu z cache.

9. **Klasyfikacja: kategoria domyślna źródła ∪ dopasowania słów kluczowych.**
   Słowa w `NewsCore/Sources/NewsCore/Resources/keywords.json`, osobno dla `pl`/`en`/`de` + lista `common` (nazwy własne, tickery). Dopasowanie bez rozróżniania wielkości liter i znaków diakrytycznych (`ł→l`, `ß→ss`), na granicach słów. `słowo*` = prefiks (ważne dla odmiany w PL/DE), frazy wielowyrazowe dozwolone, także z prefiksami (`stop* procentow*`). Domyślnie wystarcza 1 trafienie (`minimumMatches`). Artykuł może mieć kilka tematów lub żadnego (wtedy widoczny tylko w „Wszystkie”).

10. **Tematy (identyfikatory):** `finance`, `politics`, `breakthroughs` (nauka/technologia), `crypto`, `economy`. Polskie nazwy wyświetlane są w warstwie UI.

11. **Deduplikacja: znormalizowany URL lub znormalizowany tytuł.**
    URL: `https`, bez `www.`/`m.`/`amp.`, bez fragmentu, bez parametrów śledzących (`utm_*`, `fbclid`, …), bez końcowego `/` i `/amp`, posortowane parametry. Tytuł: bez diakrytyków i interpunkcji; porównywany tylko gdy ma ≥ 20 znaków (żeby nie łączyć „Live updates”). Scalony wpis: suma tematów, najdłuższy opis, najwcześniejsza data, lista pozostałych źródeł. ID artykułu = FNV-1a z znormalizowanego URL (stabilne między uruchomieniami).

12. **Treść: tylko nagłówek, opis z RSS (HTML usunięty, max 300 znaków), źródło, data, link.** Pełnych artykułów nie pobieramy. Oryginał otwiera się w `SFSafariViewController` (oraz „Otwórz w przeglądarce” w menu kontekstowym).

13. **Filtrowanie:** pusty zbiór tematów/języków = wszystkie. Wybrane tematy działają jak „LUB”, tematy i języki łączone przez „I”. Wyszukiwanie: każde słowo zapytania musi być prefiksem słowa w tytule, opisie, streszczeniu AI lub nazwie źródła (bez diakrytyków).

14. **Odporność na błędy:** każde źródło pobierane równolegle (`TaskGroup`), błąd HTTP/sieci/parsowania trafia do `failures` i jest pokazywany w UI (baner + ekran źródeł), reszta listy działa normalnie. Po nieudanym odświeżeniu zostają artykuły z cache.

15. **Odświeżanie:** przy starcie z cache; automatyczne pobranie, jeśli cache jest starszy niż 15 min; ręcznie pull-to-refresh. Brak pracy w tle i powiadomień (MVP).

## Źródła

16. **Źródła RSS (26 kanałów: 12 EN, 6 PL, 8 DE)** – renomowane media z darmowymi kanałami bez kluczy (BBC, The Guardian, CNBC, NPR, ScienceDaily, Nature, Ars Technica, CoinDesk, Cointelegraph, Bankier.pl, Polsat News, TVN24, Nauka w Polsce, Rzeczpospolita, tagesschau, DER SPIEGEL, Handelsblatt, heise, BTC-ECHO).
    **Wszystkie mają `"verified": false`** – proxy środowiska chmurowego blokuje te domeny, więc nie dało się sprawdzić adresów. Aplikacja pokazuje nieudane źródła; do weryfikacji lokalnie (patrz `PROGRESS.md`). Źródła można wyłączać w Ustawieniach.

## AI (etap opcjonalny)

17. **Integracja z Claude API przez surowe HTTP** – brak oficjalnego SDK dla Swifta. Endpoint `POST /v1/messages`, nagłówki `x-api-key`, `anthropic-version: 2023-06-01`, odpowiedź strukturalna przez `output_config.format` (JSON Schema: `topics`, `summary`), `effort: "low"`.
18. **Domyślnie wyłączona.** Włączenie wymaga zapisania klucza; klucz tylko w Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), nigdy w kodzie/repo/konfiguracji. `NewsCore` nie przechowuje klucza – dostaje go przy wywołaniu.
19. **Model domyślny `claude-opus-5`** (zgodnie z aktualnymi zaleceniami Anthropic), z wyborem w Ustawieniach (`claude-sonnet-5`, `claude-haiku-4-5` – tańsze). Dla Opus 5 włączone `fallbacks: "default"` (nagłówek `anthropic-beta: server-side-fallback-2026-07-01`), aby odmowa klasyfikatora była automatycznie ponawiana na innym modelu. Obsługa `stop_reason: "refusal"`.
20. **Kontrola kosztów:** maks. 10 artykułów na jedno odświeżenie, tylko te bez streszczenia AI, wysyłany jest wyłącznie nagłówek i krótki opis. Błąd 401/403 przerywa partię; pojedyncze inne błędy są pomijane. Testy wyłącznie na mockach – żadnych płatnych wywołań podczas pracy.

## Proces

21. **Branch:** praca na `claude/keen-goodall-cj91f0` (branch wyznaczony dla tej sesji) zamiast `feature/mvp`.
22. **Repozytorium było puste (brak `main`).** Utworzenie `main` przez push zostało zablokowane przez uprawnienia sesji, a push brancha zwrócił 403 (brak dostępu aplikacji Claude GitHub do repo). Commity są lokalne – patrz „Do zrobienia lokalnie” w `PROGRESS.md`.
23. **Toolchain Swift w chmurze:** `download.swift.org` zablokowany przez proxy, więc Swift 6.2.4 został rozpakowany z oficjalnego obrazu Docker `swift:6.2.4-noble` (do `/opt/swiftroot`, poza repo).
