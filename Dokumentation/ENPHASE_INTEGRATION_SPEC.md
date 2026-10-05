# PV-Anlage (Enphase) neben der Wärmepumpe integrieren — Spezifikation

Diese Spezifikation beschreibt, wie die App neben der Viessmann-Wärmepumpe auch die Enphase-PV-Anlage anzeigt und deren Tageswerte speichert, damit beide Datenquellen später gemeinsam betrachtet (und irgendwann gemeinsam exportiert) werden können. Grundlage ist die API-Recherche in `ENPHASE_API_WERTE.md` (gleiches Verzeichnis).

## Geklärte Eckpunkte

- Enphase-Zugangsdaten (Client-ID, Client-Secret, API-Key) sind vorhanden.
- Die Anlage hat einen Batteriespeicher (Encharge) — "Speicherzustand" kommt aus echten Gerätedaten.
- Neue, eigene Sidebar-Sektion **"PV-Anlage"** (Autarkiegrad, Verbrauch, Speicher, Produktion, Einspeisung), analog zu den bestehenden Wärmepumpen-Detailsektionen. Der bestehende Energie-Tab (Wärmepumpe) bleibt unverändert — die Zusammenführung beider Datenquellen passiert vorerst nur "im Kopf" des Nutzers und später beim Export.
- OAuth-Login springt wie bei Viessmann automatisch per Custom-URL-Scheme in die App zurück, nicht per Code-Copy-Paste. Dafür muss der Nutzer die Redirect-URI vorher selbst im Enphase-Entwicklerportal eintragen (siehe unten).
- Export ist bewusst **nicht** Teil dieser Runde.
- ~~Wärmepumpe und PV-Anlage pollen gleichzeitig, alle 15 Minuten~~ — **überholt, siehe "Nachtrag 2026-09-27" am Ende dieser Datei:** Enphase erlaubt max. 1000 Abfragen/Monat, ein 15-Minuten-Takt bräuchte ca. 14.400/Monat. Beide Systeme laufen jetzt unabhängig in ihrem eigenen Takt (Wärmepumpe wieder alle 10 Minuten, PV-Anlage adaptiv nach Restbudget).
- Beide Datenquellen fallen **unabhängig voneinander** aus/laufen unabhängig — durch zwei eigenständige Model-Klassen mit je eigenem Task-Loop.
- PV-Kennzahlen lassen sich auch **rückwirkend** abrufen: Fehlen Tage in der lokalen Speicherung (App lief nicht, Erstinstallation), werden sie automatisch nachgeladen.
- **Einspeisung** wird als eigener Wert geführt (nicht nur als Rechengröße für den Autarkiegrad), zusammen mit einer **geschätzten Einspeisevergütung** (deutscher Privathaushalt) als grober, einstellbarer Richtwert — keine verbindliche Abrechnungsgröße.

## Rechercheergebnisse, die die Architektur bestimmen

**Rate-Limits.** Enphase begrenzt pro Minute **und** pro Monat (`ENPHASE_API_WERTE.md`, Abschnitt "Zugriff"). Die Doku empfiehlt selbst, das Poll-Intervall an der 15-Minuten-Auflösung der Zähler-Telemetrie auszurichten. Die PV-Anbindung bekommt deshalb ein eigenes Modell (`SolarModel`) mit eigenem State und eigenem Poll-Loop, statt in `DashboardModel` mit hineingebaut zu werden.

**Rückwirkendes Nachladen ist möglich.** Die fünf Enphase-`_lifetime`-Endpunkte (Tages-Zeitreihen für Produktion/Verbrauch/Netzbezug/Einspeisung/Batterie) sind von der "2 Jahre zurück"-Grenze der 15-Minuten-Telemetrie **nicht** betroffen — die Doku zeigt dort explizit ein Beispiel-Startdatum "2013-01-01" und eigene `start_date`/`end_date`-Parameter, während die 2-Jahres-Regel nur im separaten Abschnitt zu den Telemetrie-Endpunkten steht. Nachladen über einen großen Zeitraum ist also mit **einem** Request pro Endpunkt möglich.

## Endpunkt-Auswahl (aus `ENPHASE_API_WERTE.md`)

Für die laufenden ("heute")-Werte reichen **fünf Endpunkte pro Poll**:

| Wert | Endpunkt | Feld |
|---|---|---|
| Produktion (heute) | `GET /systems/{id}/summary` | `energy_today` (Wh) — fertiger Zähler, kein Aufsummieren nötig |
| Verbrauch (heute) | `GET /systems/{id}/telemetry/consumption_meter` (Default-Start = Mitternacht heute) | Summe aller `intervals[].enwh` |
| Netzbezug (heute, Zwischenwert für die Autarkiegrad-Formel) | `GET /systems/{id}/energy_import_telemetry` | Summe aller `intervals[][].wh_imported` |
| Einspeisung (heute) | `GET /systems/{id}/energy_export_telemetry` | Summe aller `intervals[][].wh_exported` |
| Speicherzustand | `GET /systems/{id}/telemetry/battery` | letztes Intervall: `soc.percent`; Summe `charge.enwh`/`discharge.enwh` für "heute geladen/entladen" |

**Autarkiegrad** wird berechnet, nicht abgefragt: `(Verbrauch − Netzbezug) / Verbrauch`.

Für die **rückwirkende Nachladung** fehlender Tage kommen die fünf `_lifetime`-Endpunkte zum Einsatz (je ein Request für den gesamten fehlenden Zeitraum): `energy_lifetime` (`production[]`), `consumption_lifetime` (`consumption[]`), `energy_import_lifetime` (`import[]`), `energy_export_lifetime` (`export[]`), `battery_lifetime` (`charge[]`/`discharge[]`). Der Ladezustand in Prozent (`soc.percent`) existiert **nicht** als Tages-Zeitreihe — für nachgeladene Tage bleibt `batterySocPercent` deshalb `nil`, nur ab dem ersten echten Poll wird er live erfasst.

## Umsetzung (Branch `feature/enphase-pv-integration`)

### 1. Auth: `EnphaseOAuthClient.swift`, `EnphaseEndpoints.swift`

Strukturell wie `OAuthClient.swift`/`ViessmannEndpoints.swift`, aber mit dokumentierten Abweichungen:
- **Zwei Geheimnisse statt einem:** `client_id` **und** `client_secret` (HTTP-Basic beim Token-Tausch) **und** ein separater API-Key (Header `key:` auf **jedem** API-Request, nicht nur beim Login).
- **Token-Tausch als Query-Parameter, kein Body:** `POST /oauth/token?grant_type=...&redirect_uri=...&code=...` — anders als Viessmanns Form-Body. Eigene `postToken`-Implementierung, nicht die von `OAuthClient` wiederverwenden.
- Redirect: `de.florian.tobias.Dashboard-Waermepumpe://enphase-oauth-callback` — derselbe bereits registrierte URL-Scheme wie bei Viessmann (`Dashboard-Waermepumpe-Info.plist`, `CFBundleURLTypes`), nur ein anderer Pfad; `ASWebAuthenticationSession` prüft nur das Scheme, keine Info.plist-Änderung nötig.
  - **Manueller Schritt des Nutzers (nicht durch uns machbar):** Diese Redirect-URI muss vorher in der eigenen Enphase-Developer-App im Portal eingetragen werden.
- Kein PKCE laut Doku (nur `response_type=code&client_id=...`), da vertraulicher Client mit Secret.
- Token-Antwortformat wird als `access_token`/`refresh_token`/`expires_in` **angenommen** (laut `ENPHASE_API_WERTE.md` noch nicht an echten Daten verifiziert) — `TokenResponse`/`StoredTokens` aus `OAuthClient.swift` sind vom Shape her identisch und werden wiederverwendet; `TokenStore` ebenso, mit eigenem Dateinamen (`enphase-tokens.json`).
- Sollte sich das Antwortformat beim ersten echten Login als abweichend herausstellen, wird das hier nachgezogen und in `ENPHASE_API_WERTE.md` nachgetragen (wie dort selbst vermerkt).

### 2. `EnphaseSettings.swift`

Wie `PressureAlertSettings.swift`: `@Observable`, `UserDefaults`-Backing mit injizierbarem Store, explizite Setter. Felder: `clientID`, `clientSecret`, `apiKey` (alle zunächst leer, vom Nutzer in der neuen Login-Ansicht einzutragen), sowie **`feedInTariffPerKWh`** (Default **0,08 €/kWh** — grober Richtwert für die Überschusseinspeisung kleiner privater Anlagen in Deutschland, degressiv und je nach Inbetriebnahmedatum unterschiedlich; im Zweifel den tatsächlichen, im EEG-Anlagenregister hinterlegten Satz eintragen). Client-Secret liegt damit — wie schon die Viessmann-/Enphase-Tokens — als Klartext in den App-Einstellungen; für dieses rein lokale Ein-Personen-Tool ist das dieselbe, bereits akzeptierte Sicherheitsabwägung wie beim Rest der App (Sandbox ist ohnehin bereits deaktiviert).

### 3. `EnphaseClient.swift`, `EnphaseDTO.swift`

Wie `ViessmannClient.swift`/`ViessmannDTO.swift`. Jeder Request setzt **beide** Header (`Authorization: Bearer <token>`, `key: <apiKey>`). DTOs für die fünf "heute"-Endpunkte (`SystemSummary`, `MeterTelemetry` mit `intervals[].enwh` für Verbrauch, `ImportExportTelemetry` mit den verschachtelten `intervals[][]` für Netzbezug/Einspeisung, `BatteryTelemetry` mit `soc.percent`/`charge.enwh`/`discharge.enwh`) sowie die fünf `_lifetime`-Tagesarrays für die Nachladung (`LifetimeSeries` mit jeweils `start_date` + einem Wh-Array). System-Auflistung (`GET /systems`) für die Systemerkennung.

### 4. `Model/PVDailySample.swift` (neu, SwiftData)

Eigenes Modell statt Wiederverwendung von `EfficiencySample` — andere Datenquelle, anderes Polling, klar getrennt (wie bereits `FeatureSample` vs. `EfficiencySample` getrennt sind):
```swift
@Model final class PVDailySample {
    var date: Date              // lokaler Tagesbeginn, wie bei EfficiencySample .day/.week
    var producedWh: Double
    var consumedWh: Double
    var importedWh: Double
    var exportedWh: Double
    var batterySocPercent: Double?      // nil bei nachgeladenen Tagen
    var batteryChargedWh: Double
    var batteryDischargedWh: Double

    var selfSufficiencyRate: Double? {  // Autarkiegrad, wie EfficiencySample.efficiency berechnet
        consumedWh > 0 ? (consumedWh - importedWh) / consumedWh : nil
    }

    // Vergütung ist ein einstellbarer Wert (EnphaseSettings.feedInTariffPerKWh), deshalb als
    // Parameter statt als reine gespeicherte/berechnete Eigenschaft — Schätzwert, keine
    // verbindliche Abrechnungsgröße.
    func estimatedFeedInRevenue(tariffPerKWh: Double) -> Double {
        exportedWh / 1000 * tariffPerKWh
    }
}
```
Wird bei jedem Poll für den **heutigen** Tag upgesertet (gleiches Muster wie `DashboardModel.upsertContinuousSample` für `.day`/`.week`) — ein Eintrag pro Kalendertag, so entsteht die Tageshistorie ganz von selbst, ohne eigene Aufräum-/Prune-Logik. Von der Nachladung betroffene Tage werden genauso upgesertet, nur rückwirkend und ohne `batterySocPercent`.

### 5. `SolarModel.swift` (neu) — eigener State/Poll-Loop, analog `DashboardModel`

- State-Enum wie `DashboardState`, aber mit drei Enphase-Feldern statt nur einer Client-ID: `.needsCredentials` (Client-ID/Secret/API-Key fehlen), `.needsSignIn`, `.loading`, `.ready`, `.rateLimited`, `.error`.
- `resolveSystem()` analog `resolveInstallation()`: einmalig `GET /systems` abfragen, `system_id` cachen (neues `Model/EnphaseSystem.swift`, wie `Installation.swift`); bei genau einem System automatisch übernehmen, bei mehreren vorerst das erste.
- `pollOnce()`: die fünf "heute"-Endpunkte abrufen, `PVDailySample` für heute upserten, `state` setzen. Rate-Limit-Handling wie bei `ViessmannClient` (HTTP 429 → `Retry-After`/`period_end` auswerten, weiterlaufen statt abzubrechen).

**Gleichzeitiges, aber unabhängiges Polling.** `pollInterval` beider Modelle wird auf **900 s (15 Minuten)** vereinheitlicht — `DashboardModel.pollInterval` ändert sich damit von 10 auf 15 Minuten. `Dashboard_WaermepumpeApp.init()` startet `dashboardModel.startPolling()` und `solarModel.startPolling()` unmittelbar nacheinander, sodass beide Loops zur gleichen Zeit beginnen und im Gleichschritt bleiben. Da jedes Modell seinen eigenen Task-Loop und eigenen State hat, bleibt ein Fehler/Rate-Limit im einen Modell für das andere folgenlos.

**Historische Nachladung fehlender Tage.** Neue Methode `backfillMissingDays(into:)`, einmalig beim Start aufgerufen (vor dem ersten regulären Poll):
1. Vorhandene `PVDailySample`-Tage aus SwiftData laden, den frühesten und den heutigen Tag bestimmen.
2. Fehlende Tage dazwischen ermitteln (Lücken, z. B. weil die App zwischenzeitlich nicht lief).
3. **Erstlauf ohne jede Historie:** Standardmäßig werden die letzten **30 Tage** nachgeladen (empfohlener Startwert, über eine Konstante leicht änderbar) statt der kompletten Anlagen-Lebenszeit.
4. Für den ermittelten Zeitraum je **einen** Request an die fünf `_lifetime`-Endpunkte, Arrays tagesweise ab `start_date` ausrichten, fehlende Tage als `PVDailySample` einfügen (`batterySocPercent = nil`).
5. Nachträgliche Lücken werden beim nächsten App-Start genauso erkannt und nachgeladen — kein separater Zeitplan nötig.

### 6. `SolarView.swift` (neu) — die Sidebar-Ansicht "PV-Anlage"

Gleiches Baukasten-Prinzip wie die bestehenden Detail-Sektionen (`DetailCard`/`InfoRow`/`formattedMeasurement` aus `DetailSectionComponents.swift`):
- Ist `SolarModel.state` `.needsCredentials`/`.needsSignIn`: eine kompakte Login-Ansicht (Felder Client-ID/Client-Secret/API-Key, "Anmelden"-Button) direkt in dieser Sektion.
- Danach: Kennzahlenkarten **Autarkiegrad** (%), **Verbrauch** (kWh), **Produktion** (kWh), **Einspeisung** (kWh, mit geschätzter Vergütung in € als kleinerer Zusatztext darunter) — sowie eine **Speicherzustand**-Karte (Ladezustand % + heute geladen/entladen kWh).
- Balkendiagramm im Stil von `EnergyView` (Produktion/Verbrauch/Einspeisung je Tag über die gespeicherten `PVDailySample`-Reihen, gleiche `SeriesColors`/Chart-Konventionen), da durch die Nachladung echte Mehrtages-Historie vorliegt.

### 7. Sidebar/App-Verdrahtung

- `AppSection` (`AppWindowView.swift`): neuer Fall `.solar`, Titel "PV-Anlage", Icon (vor Verwendung per `NSImage(systemSymbolName:)` verifizieren). Einsortierung direkt nach `.overview`.
- `Dashboard_WaermepumpeApp.swift`: `SolarModel()` analog `DashboardModel()` erzeugen, `modelContext` zuweisen, Polling starten. Schema um `PVDailySample.self`, `EnphaseSystem.self` erweitern.

### 8. Tests

Gleiche Konventionen wie beim Rest der Suite (`Support/TestSupport.swift`, `StubURLProtocol`, injizierbare `UserDefaults`/`URLSession`/Uhr):
- `EnphaseDTOTests` (Decoding aller fünf Antwortformen inkl. der `_lifetime`-Tagesarrays).
- `PVDailySampleTests` (`selfSufficiencyRate`, `estimatedFeedInRevenue(tariffPerKWh:)`).
- `SolarModelTests`: Poll-Upsert-Verhalten, `backfillMissingDays` (Lücken zwischen Tagen, Erstlauf-Fenster, `batterySocPercent == nil` bei nachgeladenen Tagen).
- `EnphaseOAuthClientTests` analog `OAuthClientTests`.
- `DashboardModelTests`: Anpassung auf `pollInterval == 900`.

### 9. Bekannte Einschränkungen

- Token-Antwortformat ungetestet (siehe `ENPHASE_API_WERTE.md`).
- Client-Secret liegt im Klartext in `UserDefaults`.
- Export folgt später.
- Mehrfachanlagen werden nicht unterstützt.
- `batterySocPercent` fehlt bei nachgeladenen Tagen (keine Tages-Zeitreihe für SOC verfügbar).
- Einspeisevergütung ist ein grober, manuell einzustellender Schätzwert ohne Bezug zu einer echten Abrechnung.
- Standard-Nachladefenster bei Erstlauf ist auf 30 Tage begrenzt.

## Verifikation

1. Build, Warnungen prüfen.
2. Neue SF-Symbol-Namen vor Einbau gegen `NSImage(systemSymbolName:)` prüfen.
3. Tests laufen lassen, danach Coverage-Skript (neue Dateien ergänzen).
4. Gegen die echte Datenbank prüfen, dass `backfillMissingDays` die letzten 30 Tage angelegt hat und der Poll-Loop danach einen vollständigen Eintrag für heute erzeugt.
5. Manuell durch den Nutzer: Redirect-URI im Enphase-Portal eintragen, Login durchklicken, plausible Werte prüfen.

## Nachtrag 2026-09-27: Wertereihen-Auswahl, Monats-/Jahreswerte, Enphase-Abfragebudget

Zusätzliche Anforderungen: Wertereihe (Alle/Produktion/Verbrauch/Einspeisung) auswählbar, Monatswerte der letzten 12 Monate und Jahreswerte anzeigen. Nachträglich vorgegebene harte Grenzen der Enphase-API: **max. 10 Abfragen/Minute und max. 1000 Abfragen/Monat** (siehe Projekt-Memory "Enphase API-Limits"). Diese Grenzen machten den oben beschriebenen 15-Minuten-Gleichschritt mit der Wärmepumpe hinfällig (ein 15-Minuten-Takt bräuchte ca. 14.400 Abfragen/Monat, das 14-Fache) und zeigten, dass auch der App-Start selbst (1 `systems` + 5 Backfill + 5 Poll = 11 Abfragen in Sekunden) das Minutenlimit riss.

**Umsetzung (Branch `feature/pv-series-selection-and-periods`):**

- **`Enphase/EnphaseRequestThrottle.swift`** (neu): gleitendes 60-Sekunden-Fenster, `acquire()` vor jeder Abfrage in `EnphaseClient.perform(url:)`. Sind im Fenster schon 10 Abfragen gelaufen, wird gewartet, bis die älteste herausfällt (+1 s Puffer). `SolarModel` hält eine Instanz, geteilt zwischen Nachladen und regulärem Poll.
- **`Enphase/EnphaseRequestBudget.swift`** (neu): persistenter Zähler pro Kalendermonat (`UserDefaults`, Reset bei Monatswechsel). `nextPollDelay(used:now:)` verteilt das Restbudget (abzüglich Reserve und einer täglichen Abschluss-Reservierung von 5 Abfragen je Resttag) gleichmäßig auf den Rest des Monats, minimal 15 Minuten; `nil`, wenn für weitere Live-Polls kein Budget mehr übrig ist. Ist das Budget (abzüglich halber Reserve) faktisch aufgebraucht, wirft `EnphaseClient.perform(url:)` `monthlyBudgetExhausted`, **ohne** die Abfrage abzuschicken.
- **`EnphaseClient.swift`**: `perform(url:)` prüft zuerst das Monatsbudget, drosselt dann über `EnphaseRequestThrottle`, zählt danach jede tatsächlich abgeschickte Abfrage. `checkStatus` wertet bei `429` zusätzlich den Antwort-Body aus (`period_end`, Unix-Sekunden) — genauer als der generische `Retry-After`-Header und deckt sowohl Minuten- als auch Monats-Sperren ab.
- **`SolarModel.swift`**: kein fester `pollInterval` mehr. `pollOnce()` gibt `EnphaseRequestBudget.nextPollDelay(...)` zurück (Fallback: Zeit bis Mitternacht, falls kein Live-Poll-Budget mehr übrig ist). `lastPollAt` wird persistiert, sodass ein App-Neustart nicht sofort einen weiteren Live-Poll auslöst. Ein täglicher, höchstens einmal pro Kalendertag laufender "Abschluss"-Durchlauf (`runDailyFinalizeIfNeeded`, gleiches Gate wie beim einmaligen Ur-Backfill) holt über die `_lifetime`-Endpunkte die endgültigen Werte für noch nicht abgeschlossene Tage nach — `backfillMissingDays` deckt damit jetzt sowohl den Erstlauf als auch die tägliche Nachpflege ab, ein Mechanismus statt zwei.
- **`Model/PVDailySample.swift`**: neues Feld `isFinal: Bool` (Default `false`). Der heutige, live gepollte Tag bleibt nicht-final; der tägliche Abschluss-Durchlauf überschreibt jeden nicht-finalen Tag mit dem Wert aus der `_lifetime`-Serie und markiert ihn final. **Nachlaufende Nullen** in der `_lifetime`-Serie ("noch nicht gemeldet", siehe `ENPHASE_API_WERTE.md`) werden **nicht** übernommen — der Tag bleibt nicht-final für einen erneuten Versuch am nächsten Tag.
- **Komplette Historie statt 30-Tage-Fenster**: `EnphaseSystemInfo`/`EnphaseSystem` bekommen ein Feld `operationalAt` (`operational_at` aus `GET /systems`, Unix-Sekunden — Inbetriebnahme-/Netzanschlusszeitpunkt). Der Abschluss-Durchlauf lädt ab diesem Datum nach (Fallback weiterhin 30 Tage, falls `operational_at` unbekannt bleibt). Ein Alt-Cache ohne `operationalAt` (Stand vor dieser Änderung) löst einmalig ein erneutes `GET /systems` aus, um das Feld nachzutragen.
- **`Enphase/PVPeriodAggregation.swift`** (neu, reine Logik ohne zusätzliche Abfragen): `lastTwelveMonths(_:now:)` liefert immer genau 12 Einträge (aktueller Monat + 11 vorherige, auch leere Monate), `years(_:now:)` liefert einen Eintrag pro Kalenderjahr vom frühesten gespeicherten Tag bis zum laufenden Jahr — beide aus den lokal gespeicherten `PVDailySample`-Tageswerten aufsummiert, jeweils mit `isRunning`-Flag für den laufenden Zeitraum.
- **`EnphaseSettings.swift`**: neues `enum PVSeriesSelection { all, production, consumption, feedIn }`, persistiert (`seriesSelection`/`setSeriesSelection(_:)`) — eine gemeinsame Auswahl für alle drei Diagramme.
- **`SolarView.swift`**: segmentierter Picker über den Diagrammen; ein generischer `SolarSeriesChart` (über ein privates `PVSeriesBar`-Protokoll, dem sowohl `PVDailySample` als auch `PVPeriodTotal` entsprechen) zeichnet je nach Auswahl nur die gewünschten Balkenreihen. Drei Abschnitte: Tage (letzte 30), letzte 12 Monate, Jahre. In der Einstellungen-Karte zusätzlich ein Transparenz-Hinweis "Enphase-Abfragen diesen Monat: X / 1000 · nächster Abruf ca. HH:MM".
- **`DashboardModel.pollInterval`**: zurück von 900 auf 600 Sekunden (10 Minuten) — der ursprüngliche Wert vor der PV-Integration. Beide Systeme laufen jetzt vollständig unabhängig in ihrem jeweils eigenen Takt, kein gemeinsamer Gleichschritt mehr.

**Zusätzliche bekannte Einschränkung:** Das tatsächliche Monatskontingent des jeweiligen Enphase-Entwickler-Tarifs ist nicht bekannt — 1000/Monat ist eine vom Nutzer vorgegebene Obergrenze, keine aus der API-Dokumentation verifizierte Plan-Angabe. Ist das echte Kontingent kleiner, greift nur noch das reaktive 429-Handling (`period_end` aus dem Antwort-Body).
