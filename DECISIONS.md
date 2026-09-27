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
    Początkowo wszystkie miały `"verified": false` (proxy chmury blokuje te domeny). Po pierwszym uruchomieniu na symulatorze 25 kanałów działało i ma `verified: true`; Rzeczpospolita – Ekonomia (404) dostała nowy adres `rss/451-ekonomia`, na razie niezweryfikowany. Źródła można wyłączać w Ustawieniach.

## AI (etap opcjonalny)

17. **Integracja z Claude API przez surowe HTTP** – brak oficjalnego SDK dla Swifta. Endpoint `POST /v1/messages`, nagłówki `x-api-key`, `anthropic-version: 2023-06-01`, odpowiedź strukturalna przez `output_config.format` (JSON Schema: `topics`, `summary`), `effort: "low"`.
18. **Domyślnie wyłączona.** Włączenie wymaga zapisania klucza; klucz tylko w Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), nigdy w kodzie/repo/konfiguracji. `NewsCore` nie przechowuje klucza – dostaje go przy wywołaniu.
19. **Model domyślny `claude-opus-5`** (zgodnie z aktualnymi zaleceniami Anthropic), z wyborem w Ustawieniach (`claude-sonnet-5`, `claude-haiku-4-5` – tańsze). Dla Opus 5 włączone `fallbacks: "default"` (nagłówek `anthropic-beta: server-side-fallback-2026-07-01`), aby odmowa klasyfikatora była automatycznie ponawiana na innym modelu. Obsługa `stop_reason: "refusal"`.
20. **Kontrola kosztów:** maks. 10 artykułów na jedno odświeżenie, tylko te bez streszczenia AI, wysyłany jest wyłącznie nagłówek i krótki opis. Błąd 401/403 przerywa partię; pojedyncze inne błędy są pomijane. Testy wyłącznie na mockach – żadnych płatnych wywołań podczas pracy.

## Proces

21. **Branch:** praca na `claude/keen-goodall-cj91f0` (branch wyznaczony dla tej sesji) zamiast `feature/mvp`.
22. **Repozytorium było puste (brak `main`).** Utworzono `main` z commitem startowym (`.gitignore` + README) i scalono go do brancha MVP strategią `ours` (bez przepisywania historii), aby PR miał wspólną historię z `main`. `main` jest domyślnym branchem.
23. **Toolchain Swift w chmurze:** `download.swift.org` zablokowany przez proxy, więc Swift 6.2.4 został rozpakowany z oficjalnego obrazu Docker `swift:6.2.4-noble` (do `/opt/swiftroot`, poza repo).

## Rynki i powiadomienia o cenach

24. **Dane cen: Yahoo Finance (akcje/ETF/indeksy/krypto) + CoinGecko (krypto).** Oba darmowe i bez kluczy. Yahoo to nieoficjalny endpoint `v8/finance/chart`, ale jedyny darmowy, który obejmuje też GPW (`.WA`) i giełdy europejskie; wymaga nagłówka User-Agent. CoinGecko to oficjalne publiczne API z limitem kilku zapytań na minutę. Dostawcy są za protokołem `PriceHistoryProvider`, więc można ich wymienić. Domyślnie krypto korzysta z CoinGecko.
25. **Definicja „nagłej zmiany”:** reguła = okno (godziny) + próg (%) + kierunek (wzrost/spadek/oba). Ostatnia cena porównywana z najniższą (wzrost) lub najwyższą (spadek) ceną w oknie, łącznie z ceną z początku okna. Dzięki temu gwałtowny ruch w środku okna też jest wykrywany. Wiele reguł na instrument.
26. **Każdy ruch zgłaszany raz, bez stanu per reguła:** alert jest „nowy”, gdy reguła jest spełniona teraz, a nie była spełniona (w tym samym kierunku) w chwili poprzedniego sprawdzenia, liczonej na tych samych danych. Wystarczy zapamiętać czas ostatniego sprawdzenia (aplikacja: UserDefaults; GitHub Actions: cache). Odwrócenie trendu (wzrost → spadek) generuje nowy alert.
27. **Powiadomienia, dwie darmowe ścieżki:**
    - *lokalne* (`UNUserNotificationCenter`) + sprawdzanie w tle (`BGAppRefreshTask`, identyfikator `com.example.newstracker.pricecheck`). Bez serwera, ale iOS sam decyduje o częstotliwości i nie uruchamia zadania po wymuszonym zamknięciu aplikacji;
    - *serwerowe*: GitHub Actions (cron co godzinę) uruchamia CLI `price-watch` (ten sam kod `NewsCore`) i publikuje na **ntfy.sh**. Wybrane, bo nie wymaga konta, klucza ani własnego backendu; APNs wymagałby płatnego konta deweloperskiego i serwera. Temat ntfy jest przechowywany jako sekret `NTFY_TOPIC` w GitHub, a nie w repozytorium.
28. **Konfiguracja serwerowa w `alerts.json` (katalog główny)** w tym samym formacie co lista w aplikacji. Aplikacja eksportuje listę do skopiowania. Automatyczna synchronizacja aplikacja → repo wymagałaby tokena GitHub w aplikacji, więc jej nie ma.
29. **Czas ostatniego sprawdzenia na GitHub Actions** jest trzymany w `actions/cache` (nowy klucz na każde uruchomienie, odczyt po prefiksie). Nie zapisuje go w repo, żeby workflow nie potrzebował uprawnień zapisu. Po utracie cache przyjmowany jest odstęp 60 min. Stan przesuwa się tylko po udanym wysłaniu, więc przy błędzie ntfy alerty zostaną ponowione.
30. **Info.plist:** klucze `UIBackgroundModes` i `BGTaskSchedulerPermittedIdentifiers` nie mają odpowiedników `INFOPLIST_KEY_*`, więc XcodeGen generuje `NewsTrackerApp/Info.plist` (w `.gitignore`), który Xcode łączy z kluczami generowanymi automatycznie.
31. **Branch:** funkcja rozwijana na tym samym branchu co MVP (`claude/keen-goodall-cj91f0`, PR #1), bo PR nie był jeszcze scalony, a sesja ma wyznaczony jeden branch.

## Kategorie, ignorowanie, przeczytane, archiwa

32. **`Topic` z enuma stał się otwartym typem** (`RawRepresentable` na `String`) z pięcioma wbudowanymi stałymi, żeby użytkownik mógł dodawać kategorie. Zapis w JSON bez zmian (sam string), więc stary cache działa.
33. **Własne kategorie** (`CustomCategory`: id `custom-xxxxxxxx`, nazwa, słowa kluczowe, ikona SF Symbol, kolor) klasyfikowane tylko słowami kluczowymi, wspólnymi dla wszystkich języków (lista `common`). Po zmianie przeliczane są wyłącznie tematy własnych kategorii w cache, na liście „Do przeczytania” i w archiwum przeczytanych (`Article.reclassified`). Tematy ze źródła, wbudowanych słów i AI zostają. Zapis w `categories.json`.
34. **Kategoria domyślna źródła tylko dla kanałów tematycznych.** Kanały ogólne (Bankier – wiadomości, Polsat News – Polska, tagesschau – Inland) publikują też newsy spoza swojej tematyki, co dawało błędne „Finanse”/„Polityka” (np. wypadek na przejeździe). Mają teraz `defaultCategory: null`, a temat nadają im słowa kluczowe (dodano m.in. ONZ, UE, GUS).
35. **„Ignoruj podobne” = wyciszone słowa kluczowe** (ta sama składnia co `keywords.json`), a nie automatyczne podobieństwo tekstu. Jest przewidywalne, działa offline i łatwo je cofnąć. Propozycje słów pochodzą z nagłówka (bez słów pospolitych PL/EN/DE, skróty pisane wielkimi literami zostają). Opcja „odmiany” zamienia słowo na prefiks (`Iranu` → `iran*`). Wyciszenia dotyczą tylko listy Newsy; zapisane i przeczytane są zawsze widoczne. Zapis w `mute-list.json`.
36. **Przeczytane = osobne archiwum** (`ReadArchive`, `read-archive.json`, maks. 2000 wpisów): oznaczenie przenosi news z listy „Do przeczytania” do archiwum, więc licznik na zakładce pokazuje tylko nieprzeczytane. Ponowne zapisanie przeczytanego newsa przywraca go do listy. Newsy nie są oznaczane automatycznie przy otwarciu, bo otwarcie nie oznacza przeczytania.
37. **Archiwum alertów giełdowych** to historia wykrytych alertów w aplikacji (do 1000 wpisów, `price-alerts.json`), pogrupowana po dniach, z filtrem instrumentu. Alerty wysyłane przez GitHub Actions/ntfy nie trafiają do aplikacji; ich historię przechowuje aplikacja ntfy.
38. **Wyszukiwarka instrumentów:** nieoficjalny endpoint Yahoo `v1/finance/search` (bez klucza). Przy 404 z endpointu notowań zwracany jest błąd `symbolNotFound` z podpowiedzią o sufiksach giełd, a edytor sam uruchamia wyszukiwanie.

## Źródła dodawane przez użytkownika

39. **Nowe polskie źródła** (na prośbę): money.pl (`/rss/`), Puls Biznesu (`/rss`), Business Insider Polska (`/.feed`), GPW (`/_rss`, kategoria „Finanse”), Spider's Web (`/feed`), Defence24 (`/_rss`), Zaufana Trzecia Strona (`/feed/`). Adresy pochodzą od użytkownika i z wyszukiwarki; z chmury nie dało się ich pobrać (`verified: false`). Serwisy ogólne nie mają kategorii domyślnej (decyzja 34).
40. **Automatyczne znajdowanie kanału:** gdy pod adresem źródła jest strona HTML, a nie kanał, `FeedAggregator` szuka kanału: najpierw `<link rel="alternate" type="application/rss+xml|atom+xml">`, potem linki `<a>` zawierające „rss/feed/atom/.xml”, jeden poziom w głąb (strony z listą kanałów, np. GPW), na końcu typowe ścieżki (`/feed`, `/rss`, `/rss.xml`, `/.feed`, `/_rss`…). Przy odświeżaniu maks. 6 prób i pierwszy niepusty kanał. Znaleziony adres jest zapamiętany w `NewsRepository` do końca sesji, a po błędzie wyszukiwany ponownie. Nie dotyczy odpowiedzi 404, bo strona główna serwisu mogłaby podsunąć kanał o innej tematyce niż kategoria źródła.
41. **„Dodaj źródło” w aplikacji** (`FeedDiscoverer.discover`, maks. 15 prób) pokazuje wszystkie znalezione kanały z liczbą wpisów i przykładowym nagłówkiem. Użytkownik wybiera nazwę, język i opcjonalną kategorię. Własne źródła są w `custom-sources.json` z `verified: true`, bo kanał został właśnie pobrany i sparsowany.

## Kolejne kategorie

42. **Obronność (`defense`) i Cyberbezpieczeństwo (`cybersecurity`)** zostały dodane na prośbę użytkownika jako kategorie **wbudowane**, a nie własne, żeby miały słowa kluczowe PL/EN/DE. Kategorię domyślną dostały tylko serwisy w całości o tym temacie: Defence24 (obronność) i Zaufana Trzecia Strona (cyberbezpieczeństwo). Unikam słów wieloznacznych, np. samego `cyber*` (Cybertruck, Cyberpunk) czy „włamanie” (też kradzież z mieszkania).
43. **„Bez kategorii”** to filtr (pseudo-temat `Topic.uncategorized`, nigdy nieprzypisywany artykułom), a nie ukrywanie. Wybrał go użytkownik spośród zaproponowanych opcji. Chip stoi przed „+ Dodaj” na liście Newsy i na liście „Do przeczytania”. Widok „Wszystkie” pokazuje nadal wszystkie newsy.
