# Dashboard Wärmepumpe

macOS-Menüleisten-App, die die Werte einer Viessmann-Wärmepumpe (Viessmann IoT API) und optional einer Enphase-PV-Anlage (Enphase Monitoring API v4) anzeigt.

Dieses Dokument fasst alle Erkenntnisse, Anforderungen, Vereinbarungen und Rahmenbedingungen aus der Entwicklung zusammen — als Wissensbasis für eine geplante iOS-Portierung in einem anderen Projekt. Abschnitte sind so markiert, dass klar ist, was sich 1:1 übertragen lässt und was macOS-spezifisch ist und für iOS neu durchdacht werden muss.

## Kernanforderungen (Ausgangspunkt)

Ursprünglich geforderte Kernfunktionen, unverändert gültig:
- Extraktion/Export der Rohdaten (rohe Messwerte, nicht nur aggregierte Werte)
- Grafische Darstellung (Diagramme) der Verlaufsdaten
- Anzeige aktueller/Live-Werte

Später erweitert um eine zweite, unabhängige Datenquelle (PV-Anlage), um zu zeigen, dass sich das Muster auf mehrere Fremd-APIs mit unterschiedlichen Limits/Auth-Verfahren skalieren lässt, ohne dass sie sich gegenseitig beeinflussen.

## Architektur-Überblick (übertragbar)

- **Ein `Model` pro Datenquelle, komplett unabhängig voneinander**: `DashboardModel` (Viessmann) und `SolarModel` (Enphase) haben jeweils eigenen OAuth-Client, eigenen Poll-Loop, eigenes State-Enum (`.needsCredentials`/`.needsSignIn`/`.loading`/`.ready`/`.rateLimited`/`.error`). Ein Fehler oder Rate-Limit auf einer Seite betrifft die andere nie. Dieses Muster skaliert gut auf beliebig viele weitere Datenquellen.
- **SwiftData** für Persistenz, mit injizierbarem `ModelContainer`/`ModelContext` (In-Memory für Tests).
- **Dependency Injection durchgängig**: `URLSession`, `UserDefaults`, sowie eine Uhr (`now: () -> Date`) sind überall austauschbar injiziert — kein Code greift direkt auf `.standard`/`Date()`/`URLSession.shared` zu, ohne dass das per Parameter überschreibbar wäre. Das macht praktisch die gesamte Fachlogik ohne echte Netzwerk-/Zeit-Abhängigkeit testbar.
- **Zentrale, injizierbare Drossel-/Budget-Objekte** (`EnphaseRequestThrottle`, `EnphaseRequestBudget`) statt Rate-Limiting verteilt im Code — ein einziger Ort pro Limit-Art, den man in Tests mit einer manuell steuerbaren Uhr durchtakten kann.
- **Reine Fachlogik-Typen ohne UI-Abhängigkeit** für alles, was testbar sein muss (`PressureAlertTracker.evaluate(...)`, `PVPeriodAggregation`, `EfficiencyTracker`) — Views bleiben dünn und rufen nur auf.
- **Ein Repo-Dokument pro größerem Feature** (`PV_ENPHASE_INTEGRATION_SPEC.md`) mit Stand/Entscheidungen, bevor/während es gebaut wird — hat sich bei der zweiten Datenquelle bewährt, um Architekturentscheidungen (Auth-Verfahren, Rate-Limits, Datenmodell) vor der Umsetzung festzuhalten.

## API-Integrationen

### Viessmann IoT API
- **Auth:** OAuth2 mit PKCE (`Viessmann/PKCE.swift`, `Viessmann/OAuthClient.swift`), Client-ID reicht (kein Secret nötig, PKCE ersetzt es).
- **Login-Flow:** Browser-Redirect über ein Custom-URL-Scheme zurück in die App.
- **Falle:** Das Gateway selbst (z. B. Vitoconnect) taucht in der Geräteliste eigenständig auf und liefert nur Netzwerk-Features, nicht die Heizungsdaten — das eigentliche Wärmepumpen-*Device* muss explizit ausgewählt werden, nicht einfach das erste Gerät.
- **Rate-Limit (kostenloser Tier):** kein festes Kontingent bekannt, aber ein Polling-Takt von 5–15 Minuten gilt als sicher; aktuell 10 Minuten.
- **Praktischer Vorteil der API:** liefert vorberechnete Aggregate (`currentDay`/`lastSevenDays`/`lastMonth`/`lastYear`) für Energie-Kennzahlen — deutlich einfacher, als aus der rohen Poll-Historie zu rekonstruieren. Tag/Woche werden bei jedem Poll überschrieben, Monat/Jahr einmalig pro Kalendergrenze nachgeladen (`EfficiencyTracker`).
- **Token-Speicherung:** dateibasiert im Sandbox-Container (`TokenStore.swift`), **nicht** Keychain. Grund war ein macOS-Entwicklungsartefakt (ad-hoc-Signatur ändert sich bei jedem Build, Keychain-ACL erkennt die App dadurch nicht mehr als vertraut) — **für iOS wahrscheinlich nicht relevant**, dort ist Keychain der übliche, robuste Standard und sollte neu evaluiert werden, statt diese Entscheidung blind zu übernehmen.

### Enphase Monitoring API v4
- **Auth:** eigenes OAuth ohne PKCE, Client-ID + Client-Secret + API-Key, Token-Tausch per Query-Parametern statt Body (`Enphase/EnphaseOAuthClient.swift`, `Enphase/EnphaseEndpoints.swift`).
- **Harte Limits: max. 10 Abfragen/Minute, max. 1000 Abfragen/Monat** (planabhängig, hier als feste Obergrenze angenommen). Das ist die zentrale Randbedingung der ganzen PV-Integration:
  - `EnphaseRequestThrottle`: gleitendes 75-Sekunden-Fenster (bewusst über der Ist-Grenze von 60s als Sicherheitspuffer), zentral vor jedem Request in `EnphaseClient.perform(url:)` — nicht nur als 429-Fallback.
  - `EnphaseRequestBudget`: persistenter Zähler pro Kalendermonat, verteilt das Restbudget adaptiv auf den Rest des Monats (`nextPollDelay`, nie schneller als 15 Minuten, mit Reserve für tägliche Abschluss-Requests). Bei vollem Monatsbudget ergibt das grob alle 4–5 Stunden einen Live-Abruf statt alle 15 Minuten. Persistierter `lastPollAt` verhindert einen sofortigen Extra-Poll bei jedem App-Neustart.
  - Ist das Monatsbudget (abzüglich halber Reserve) aufgebraucht, verweigert der Client weitere Abfragen bis zum Monatswechsel (`.rateLimited`), ganz ohne Netzwerkzugriff.
- **Tages-Zeitreihen sind zunächst nicht final**: nachlaufende Nullen ("noch nicht gemeldet") kommen vor. Ein täglicher "Abschluss"-Durchlauf (höchstens einmal pro Kalendertag) holt über die `_lifetime`-Endpunkte die endgültigen Werte nach; erst dann wird `PVDailySample.isFinal = true` gesetzt.
- **Backfill-Startpunkt:** `operational_at` (Inbetriebnahmedatum) aus `GET /systems`, nicht ein willkürliches festes Fenster.
- **Wechselwirkung mit der anderen Datenquelle:** Ein gemeinsamer fixer Poll-Takt für beide APIs war naiv angenommen worden und ist mit 1000 Enphase-Abfragen/Monat nicht vereinbar (ein 15-Minuten-Takt bräuchte allein dafür ~14.400 Abfragen/Monat). Lektion: **Rate-Limits jeder externen API einzeln recherchieren, bevor ein gemeinsamer Takt für mehrere Quellen angenommen wird.**

Rohe, beobachtete API-Feldbedeutungen stehen in `VIESSMANN_API_WERTE.md` und `ENPHASE_API_WERTE.md` — bei einer Portierung zuerst dort nachsehen, bevor Felder neu interpretiert werden.

## Datenmodell-Muster (SwiftData)

- **Speicherung minimieren statt alles behalten**: Nur die letzten 5 Rohantworten (`PollSnapshot`/`FeatureSample`) bleiben lokal; PV-Tageswerte älter als das Vorjahr werden zu `PVYearlySample`-Jahressummen zusammengefasst und die Tageszeilen gelöscht (`SolarModel.pruneOldDailySamplesIfNeeded`). Muster: aggregieren + Ursprungsdaten löschen, sobald ein Zeitraum abgeschlossen ist und nur noch Summen gebraucht werden.
- **Kritische SwiftData-Falle:** Ein neues, nicht-optionales `@Model`-Property braucht seinen Default **direkt an der Property-Deklaration** (`var isFinal: Bool = false`), nicht nur im eigenen `init()` — sonst erkennt SwiftDatas automatische Lightweight-Migration die Änderung nicht und die lokale Datenbank bricht mit `no such table`/`no such column` (nur über echte App-Logs sichtbar, nicht über Compiler-Fehler).
- Dieses Projekt hat **keinen** `VersionedSchema`/`SchemaMigrationPlan`, nur ein flaches `Schema([...])` in der `App`-Datei — bei mehreren Modelländerungen in kurzer Folge instabil (einmal musste die lokale Datenbank komplett gelöscht werden, um sie zu reparieren). **Für eine neue Portierung: von Anfang an einen echten Migrationsplan einplanen, dieses Projekt hat die Lücke nie geschlossen.**

## macOS-spezifische Entscheidungen — für iOS neu bewerten, nicht übernehmen

Diese Teile sind bewusste macOS-Lösungen für macOS-Probleme und haben auf iOS kein direktes Äquivalent:

- **`MenuBarExtra` + `LSUIElement`** (App läuft primär als Menüleisten-Icon ohne Dock-Icon, volle Ansicht öffnet sich optional in einem eigenen Fenster) — kein Konzept auf iOS, dort ist die App immer die volle Ansicht.
- **`ForegroundWindowTracker` / `NSApp.setActivationPolicy(.regular/.accessory)`** — verwaltet das Dock-Icon abhängig davon, ob Haupt-/Einstellungsfenster offen sind. Auf iOS entfällt das vollständig.
- **Eigene `Settings`-Scene (Cmd+,)** für alle Einstellungen (Viessmann-/Enphase-Anmeldung, Tarife, Benachrichtigungen) — auf iOS würde das ein normaler Einstellungs-Screen in der eigenen Navigation werden, kein Scene-Typ.
- **AppleScript/Nachrichten-App-Automation** für die Druckalarm-Benachrichtigung (`MessageNotifier.swift`, `NSAppleScript`) — auf iOS nicht verfügbar; müsste durch lokale Notifications oder Push (APNs) ersetzt werden. Dabei zu beachten: `AppleEventsUsageDescription`/Automation-Freigabe war auf macOS selbst mit korrekt gesetztem Entitlement zunächst unsichtbar für den Nutzer, bis die App-Sandbox komplett deaktiviert wurde (`ENABLE_APP_SANDBOX = NO`) — das war ein Kompromiss speziell für dieses rein lokale macOS-Tool, keine allgemeine Empfehlung, und hat mit iOS (das ohnehin immer sandboxed ist) nichts zu tun.
- **Kein Autostart beim Login** — bewusste macOS-Entscheidung für dieses Tool, für eine iOS-App vermutlich ohnehin nicht anwendbar.

## Übertragbare, getestete Muster

- **Swift Charts, gruppierte Balken über mehrere Kalendereinheiten** (`SolarSeriesChart`): `BarMark`/`LineMark`/`PointMark` mit `PlottableValue.value(_:_:unit:calendar:)` statt einem `start..<end`-Intervall — das ist es, was `.position(by:)` zuverlässig nebeneinander gruppiert und Swift Charts eine sinnvolle kalenderbewusste Achsenbeschriftung wählen lässt.
- **Falle dabei:** Mehrere `LineMark`s ohne unterscheidendes Attribut (`by:`) werden zu einer einzigen durchgezogenen Linie verschmolzen — eine `.annotation()` daran wird dann nur am *ersten* Mark gerendert, nicht an jedem Punkt. Für Pro-Punkt-Beschriftungen zusätzlich eigenständige `PointMark`s verwenden, die nicht verschmelzen.
- **Zweite Y-Achse simulieren**: Werte in den bestehenden kWh-Bereich hochskalieren, zweite `AxisMarks(position: .trailing)` mit eigener prozentualer Beschriftung — Swift Charts hat keine echte zweite Y-Domain pro Chart.
- **Testansatz:** Swift Testing (`import Testing`), `URLProtocol`-Stub für Netzwerk, In-Memory-`ModelContainer`, temporäre `UserDefaults`-Instanzen statt `.standard`, injizierte Uhr für alles Zeitabhängige. Kein Test berührt echte API/echte Tokens/echte Datenbank. Zielwert Testabdeckung ≥ 80 % der Fachlogik (Views ausgenommen), siehe `scripts/test-coverage.sh`.
- **State-Machine-Falle, zweimal gefunden:** `refreshState()` (sowohl in `DashboardModel` als auch ursprünglich in `SolarModel`) hatte keinen `else`-Zweig für den Fall "Zugangsdaten und Token sind beide schon gültig" — der Zustand blieb dann fälschlich beim Konstruktions-Default (`.needsCredentials`) hängen, bis der nächste Poll ihn überschrieb. Bei einer Neuimplementierung: jede State-Berechnung explizit für *alle* Kombinationen durchdenken, nicht nur die "fehlt noch etwas"-Fälle.

## Bekannte Werkzeug-/Umgebungs-Fallstricke (diese Entwicklungsumgebung)

- `defaults read <bundle-id>` lieferte in dieser Umgebung nicht immer den echten Stand. Zuverlässige Alternative: `plutil -p ~/Library/Preferences/<bundle-id>.plist`.
- Echte CoreData-/SwiftData-Laufzeitfehler zeigen sich nur in den App-Logs (`GetConsoleOutput`), nicht als Compiler- oder offensichtlicher Xcode-Fehler.
- Xcode kann über die Automatisierungsverbindung den aktiven Git-Branch **selbstständig** zurückwechseln, ohne dass ein eigener `git`-Befehl das veranlasst hat — vor jedem Commit/Push sicherheitshalber `git branch --show-current` erneut prüfen.

## Zusammenarbeits-Konventionen

Diese Regeln galten für die gesamte Entwicklung und sollten für eine Portierung in gleicher Form vereinbart werden, falls mit demselben Assistenten weitergearbeitet wird:

- Bei Unklarheiten immer nachfragen, Vorgaben kritisch prüfen und ggf. Alternativen vorschlagen statt unkritisch umzusetzen.
- Antworten auf Deutsch.
- Git-Branches: `feature/<name>` für neue Features, `fix/<name>` für Bugfixes, `release/v<major>.<minor>` für Releases.
- Nach jedem abgeschlossenen Schritt sofort committen **und pushen** — nicht erst am Ende einer größeren Aufgabe sammeln.
- `git merge` und das Löschen von Branches nur auf explizite Anweisung, nie eigenständig.
- **Ausnahme/Verschärfung:** `release/*`-Branches werden **nie** gelöscht, auch nicht bei einer pauschalen "lösche alle Branches"-Anweisung — nur wenn ein solcher Branch dabei ausdrücklich namentlich genannt wird.
- **Release-Ablauf** (Version X.Y, Build Z): alle bereits gemergten Branches außer `release/*` löschen (lokal + remote) → `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` im Xcode-Target setzen (nicht die `Info.plist` direkt, die wird generiert) → nötige Repo-Änderungen committen/pushen → `git tag -a vX.Y` setzen und pushen → `release/vX.Y` davon abzweigen und pushen → Release-Build exportieren.
- **Export-Methode dieses Projekts:** kein Apple-Entwicklerteam/Zertifikat hinterlegt (rein lokale Nutzung) — einfacher Release-Build (`xcodebuild ... -configuration Release build`) plus Kopie des `.app`-Bundles, kein `xcodebuild archive`/`-exportArchive`. Für eine iOS-App, die auf ein Gerät oder in den App Store soll, ist das nicht übertragbar — dort ist ein echtes Team/Zertifikat und ein regulärer Archiv-Export ohnehin nötig.

## Offene Punkte / bekannte Einschränkungen (Stand dieses Projekts)

- Enphase-Login mit echten Zugangsdaten nie vollständig gegen echte Hardware verifiziert (Redirect-URI-Eintrag im Entwicklerportal war der letzte offene manuelle Schritt).
- Client-Secret/API-Key/Client-ID liegen im Klartext in `UserDefaults` — für eine iOS-Portierung von Anfang an Keychain vorsehen, nicht wiederholen.
- Nur eine Installation/ein System pro Datenquelle unterstützt (keine Geräteliste für mehrere Anlagen).
- Genaues Enphase-Monatskontingent nicht offiziell verifiziert, 1000 ist eine vom Nutzer vorgegebene, nicht API-seitig bestätigte Obergrenze.
- Vollständige Liste kleinerer, laufend gepflegter Punkte: siehe `BACKLOG.md`.

## Weiterführende Dokumente in diesem Repo

- [BACKLOG.md](BACKLOG.md) — laufend gepflegte Liste aller erledigten und offenen Punkte, chronologisch.
- [PV_ENPHASE_INTEGRATION_SPEC.md](PV_ENPHASE_INTEGRATION_SPEC.md) — vollständige Spezifikation der PV-Integration inkl. Architekturentscheidungen.
- [ENPHASE_API_WERTE.md](ENPHASE_API_WERTE.md) / [VIESSMANN_API_WERTE.md](VIESSMANN_API_WERTE.md) — beobachtete, rohe API-Feldbedeutungen der beiden Anbieter.

## Tests

```bash
scripts/test-coverage.sh        # Unit-Tests + Abdeckung der Fachlogik, bricht unter 80 % ab
scripts/test-coverage.sh 90     # anderer Mindestwert
```

Alternativ in Xcode mit ⌘U. Die Tests laufen in der App als Host, die App erkennt den Testlauf und startet dann weder das Polling noch öffnet sie die echte Datenbank.
