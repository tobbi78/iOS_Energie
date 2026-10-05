# Energie

iOS-App (SwiftUI) zum Monitoring einer Photovoltaik-Anlage (Enphase) und einer Wärmepumpe (Viessmann) in einer einzigen App — inklusive Home-Screen-Widgets und Apple-Watch-Companion.

## Funktionsumfang

- **Start-Tab**: kombinierte Kennzahlen beider Quellen auf einen Blick, mit Tap-Through in den jeweiligen Bereich. Bewusst ohne Verrechnung zwischen den Quellen (z. B. "PV-Überschuss deckt X % des Wärmepumpenbedarfs") — PV und Wärmepumpe bleiben unabhängige Datenquellen.
- **PV-Anlage** (Enphase-API, OAuth2):
  - Momentanwerte: Produktion, Verbrauch, Einspeisung, Autarkiegrad, Batterie-Ladezustand, geschätzte Vergütung
  - Verlauf: Tages-/Monats-/Jahresdiagramme (Swift Charts), automatischer Backfill fehlender Tage, Pruning alter Tageswerte zu Jahressummen
  - Monatsbudget-Überwachung (Enphase erlaubt 1000 Requests/Monat), inkl. Transparenzanzeige und adaptivem Poll-Takt im Widget
- **Wärmepumpe** (Viessmann IoT-API, PKCE-OAuth2):
  - Übersicht: Außentemperatur, Warmwasser, elektrische/thermische Leistung, Effizienz
  - Detailmasken: Heizkreise, Warmwasser, Effizienz & Verbrauch mit Verlaufsdiagrammen, Verdichter/Kältekreis-Diagnose
  - Anlagendruck-Alarm als lokale Benachrichtigung
  - Vordergrund-Poll-Loop (Standard 10 Min), pausiert automatisch im Hintergrund
- **Einstellungen**: ein zentraler Tab für Zugangsdaten, Einspeisetarif, Budget-Reserve und den Anlagendruck-Alarm beider Quellen
- **Home-Screen-Widgets**: eigene Kacheln für PV, Wärmepumpe und eine kombinierte Kachel — jede pollt eigenständig im Hintergrund über App Groups/Keychain Sharing
- **Apple Watch Companion**: Watch-App und Complications (alle vier Familien) zeigen nur vom iPhone per `WatchConnectivity` übertragene Snapshots, kein eigenständiger Netzwerkzugriff auf der Uhr

## Architektur

- SwiftUI, SwiftData (+ CloudKit-Sync über den privaten Container, Fallback auf lokal-only ohne iCloud-Account)
- Pro Datenquelle ein eigenständiges Model mit eigenem State-/Poll-Loop (`SolarModel`, `HeatPumpModel`) — bewusst keine gemeinsame "Universal"-Schicht
- OAuth-Zugangsdaten/Tokens liegen im Keychain, geteilt zwischen App und Extensions über eine App Group
- Gemeinsame UI-Bausteine (`MetricCard`, `DetailSectionComponents`, Akzentfarben) unter `Energie/Energie/UI/`

### Targets

| Target | Zweck |
| --- | --- |
| `Energie` | Haupt-App (iPhone/iPad) |
| `EnergieWidgetExtension` | Home-Screen-Widgets (PV, Wärmepumpe, kombiniert) |
| `EnergieWatch Watch App` | Apple-Watch-Companion |
| `EnergieWatchWidgetExtension` | Watch-Complications |
| `EnergieTests` | Unit-Tests (Swift Testing) |
| `EnergieUITests` | UI-Tests (XCUIAutomation) |

Hinweis: Einige Dateien (z. B. `EnphaseRequestBudget`, `ViessmannEndpoints`, `WatchSnapshot`) sind byte-identisch in mehrere Targets dupliziert, da App-Extensions/Watch-Targets keinen gemeinsamen Quellcode mit der Haupt-App teilen können.

## Voraussetzungen

- Xcode mit iOS-27-SDK, Mindest-Deployment-Target iOS 27
- Kostenpflichtiger Apple Developer Account (für CloudKit-Sync, App Groups/Keychain Sharing über mehrere Targets, Apple-Watch-Deployment)
- Eigene Enphase-Entwicklerportal-Zugangsdaten (Client-ID/Secret, API-Key, hinterlegte Redirect-URI) und Viessmann-IoT-API-Zugangsdaten

## Tests

Unit- und UI-Tests laufen über die jeweiligen Xcode-Schemes (`EnergieTests`, `EnergieUITests`). Aktueller Stand: ~82 % Codeabdeckung im Gesamtprojekt (Details siehe `BACKLOG.md`).

## Dokumentation

- `BACKLOG.md` — Anforderungen, Umsetzungsstand je Feature-Branch, Architekturentscheidungen
- `Plans/Waermepumpe-Integration.md` — Architekturplan der Wärmepumpen-Integration
- `Dokumentation/ENPHASE_API_WERTE.md` / `Dokumentation/VIESSMANN_API_WERTE.md` — API-Referenz der jeweiligen Anbieter
- `Dokumentation/ENPHASE_INTEGRATION_SPEC.md` — Architekturentwurf der PV-Integration
- `Dokumentation/ERKENNTNISSE_MACOS.md` — Erfahrungsbericht aus dem macOS-Schwesterprojekt, Basis vieler Engineering-Entscheidungen hier

## Branch-Workflow

Features auf `feature/<name>`, Fixes auf `fix/<beschreibung>`, Releases auf `release/v<major>.<minor>`. Merge nach `main` und Löschen von Branches nur nach expliziter Freigabe.
