import NewsCore
import SwiftUI
import UIKit

/// Notification settings and instructions for the free server-side watcher.
struct PriceAlertsSettingsView: View {
    @Environment(MarketStore.self) private var market
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                Toggle("Powiadomienia w aplikacji", isOn: Binding(
                    get: { market.notificationsEnabled },
                    set: { value in Task { await market.setNotificationsEnabled(value) } }
                ))
                Button("Wyślij testowe powiadomienie") {
                    Task { await market.sendTestNotification() }
                }
                .disabled(!market.notificationsEnabled)
            } header: {
                Text("Lokalnie (iPhone)")
            } footer: {
                Text("Ceny są sprawdzane przy otwarciu aplikacji, przy odświeżeniu listy „Rynki” i w tle, gdy pozwoli na to iOS (zwykle co kilka godzin; nie działa po wymuszonym zamknięciu aplikacji). Jeśli iOS nie pyta o zgodę, włącz powiadomienia w Ustawieniach systemu.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Zainstaluj darmową aplikację **ntfy** na iPhonie i zasubskrybuj temat o długiej, losowej nazwie (np. `newstracker-7f3k9x2q`). Nazwa tematu działa jak hasło.")
                    Text("2. W repozytorium na GitHubie: Settings → Secrets and variables → Actions → sekret **NTFY_TOPIC** z nazwą tematu.")
                    Text("3. Skopiuj poniższą konfigurację do pliku **alerts.json** w repozytorium (zastąp zawartość) i zrób commit do `main`.")
                    Text("4. Workflow „Price watch” sprawdza ceny co godzinę i wysyła powiadomienia – także gdy telefon i aplikacja są wyłączone. Test: Actions → Price watch → Run workflow → „Send a test notification only”.")
                }
                .font(.footnote)

                Button {
                    UIPasteboard.general.string = market.exportedConfiguration()
                    copied = true
                } label: {
                    Label(copied ? "Skopiowano" : "Kopiuj alerts.json", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                ShareLink(item: market.exportedConfiguration()) {
                    Label("Udostępnij alerts.json", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Bez aplikacji: GitHub Actions + ntfy")
            } footer: {
                Text("Darmowe w ramach limitu GitHub Actions (repozytorium publiczne – bez limitu; prywatne – 2000 min/mies., sprawdzanie co godzinę mieści się w limicie). Po przekroczeniu limitu workflow po prostu się zatrzymuje, jeśli nie ustawiono płatnego limitu wydatków.")
            }

            Section {
                Button("Przywróć domyślną listę", role: .destructive) {
                    market.resetToDefaults()
                }
            }
        }
        .navigationTitle("Powiadomienia o cenach")
    }
}
