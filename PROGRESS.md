# PROGRESS – News Tracker

## Plan

1. Szkielet repo: `.gitignore`, `PROGRESS.md`, `DECISIONS.md`, README.
2. `NewsCore` (Swift Package, bez UI):
   - modele (`Article`, `Topic`, `Language`, `FeedSource`),
   - parser RSS 2.0 / RSS 1.0 (RDF) / Atom (`XMLParser`, warunkowy import `FoundationXML`),
   - czyszczenie HTML i parsowanie dat,
   - klasyfikator słów kluczowych (PL/EN/DE) + kategoria źródła,
   - deduplikacja (znormalizowany URL + tytuł),
   - filtrowanie (tematy, języki) i wyszukiwanie,
   - pobieranie równoległe z izolacją błędów (awaria jednego źródła nie psuje listy),
   - prosty cache JSON + lista „do przeczytania”,
   - konfiguracja: `sources.json`, `keywords.json`.
3. Testy jednostkowe na fixtures (bez sieci).
4. Aplikacja iOS (SwiftUI, iOS 17) + `project.yml` (XcodeGen).
5. README z instrukcją krok po kroku.
6. Etap opcjonalny: integracja z Claude API (domyślnie wyłączona, klucz w Keychain, testy na mockach).
7. Pull Request do `main`.

## Zrobione

_(uzupełniane na bieżąco)_

## Następne

_(uzupełniane na bieżąco)_

## Znane problemy

_(uzupełniane na bieżąco)_

## Do zrobienia lokalnie

_(uzupełniane na bieżąco)_
