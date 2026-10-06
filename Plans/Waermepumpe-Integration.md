# Plan: Wärmepumpen-Integration (Viessmann) + zentraler Home-Bildschirm

Status: **Planung, nicht umgesetzt.** Dieses Dokument beschreibt das Vorgehen, bevor Code geschrieben wird. Quellen: `VIESSMANN_API_WERTE.md` (reale, beobachtete API-Werte eines `Vitocal250A`), `ERKENNTNISSE_MACOS.md` (Erfahrungen aus dem macOS-Schwesterprojekt, das Viessmann bereits produktiv integriert hat) und `BACKLOG.md` (Abschnitt "Zukünftige zweite Energiequelle: Wärmepumpe", der diese Erweiterung bereits architektonisch vorbereitet hat).

## 1. Ziel

Die App bekommt eine zweite, unabhängige Energiedatenquelle (Viessmann-Wärmepumpe) neben der bestehenden PV-Integration (Enphase). Gewünschte Struktur (Vorgabe):

1. **Zentraler Home-Bildschirm** beim App-Start: kombinierte KPIs aus PV **und** Wärmepumpe.
2. Je eine **Übersichtsmaske** für PV und für die Wärmepumpe.
3. Pro Gerät (PV, Wärmepumpe) **1–n Detailmasken** unterhalb der Übersicht.

## 2. Datengrundlage (aus `VIESSMANN_API_WERTE.md`)

Das beobachtete Gerät (`Vitocal250A`, 2 Heizkreise: Heizkörper/Fußbodenheizung) liefert u. a.:

- **Heizkreise**: Vorlauftemperatur, Soll-/Ist-Temperatur, Betriebsmodus/-programm, Heizkurve, Zeitplan — pro Heizkreis (`N`).
- **Warmwasser**: Speichertemperatur, Solltemperatur, Modus, Zirkulationspumpe + Zeitplan.
- **Wärmepumpe/Kältekreis**: Verdichterstatus, -drehzahl, -statistik (Laufzeit/Starts), diverse Temperatur-/Drucksensoren (Verdichter, Verdampfer, Kondensator, Wechselrichter) — eher Diagnose-/Technik-Werte als Alltags-KPIs.
- **Allgemeine Sensoren**: Außentemperatur, Rücklauftemperatur, **Anlagendruck** (`heating.sensors.pressure.supply`, bar) — im macOS-Projekt bereits Grundlage einer Druckalarm-Funktion (`PressureAlertTracker`).
- **Effizienz & Verbrauch** — der wichtigste Fund für die UI-Planung: `heating.power.consumption.summary.*` und `heating.heat.production.summary.*` liefern **vorberechnete Fenster** (`currentDay`/`currentMonth`/`currentYear`/`lastMonth`/`lastSevenDays`/`lastYear`) direkt von Viessmann, ebenso `heating.scop.*`/`heating.spf.*` (Seasonal COP/Performance Factor). Das ist serverseitig bereits aggregiert — anders als bei Enphase, wo wir das selbst aus Rohdaten berechnen mussten.
- Die Zeitreihen-Variante (`heating.power.consumption.heating/.dhw/.total` mit `day`/`week`/`month`/`year`) liefert auf diesem Gerät kommagetrennte Strings statt Zahlen und ist bewusst **nicht** als primäre Quelle vorgesehen (Decoder-Aufwand lohnt sich erst, wenn die `.summary`-Fenster nicht reichen).
- **Gerät/System**: Seriennummer, Firmware-Version, Zigbee-Status, Sperrzustände.
- **Meldungen** (`device.messages.*`): aktuell leer, aber vorgesehen für Info-/Service-/Statusmeldungen.
- **Netzwerk**: nur `tcu.wifi` (Signalstärke des Gateways) gehört zum echten Gerät — das Gateway-Pseudogerät selbst liefert weitere, hier irrelevante Netzwerk-Features (siehe Falle unten).

Wichtige Einschränkung: Diese Liste ist eine Momentaufnahme **dieses** Geräts. Andere Wärmepumpen-Modelle/Firmware-Stände können mehr/weniger Heizkreise oder optionale Features haben — die Implementierung sollte daher dieselbe Vorsicht walten lassen wie bei Enphase (defensives Decoding, fehlende Felder nicht als Fehler werten).

## 3. Architekturprinzipien (übernommen aus `ERKENNTNISSE_MACOS.md` / `BACKLOG.md`)

- **Eigenes `Model` für die Wärmepumpe, komplett unabhängig von `SolarModel`**: eigener OAuth-Client, eigener Poll-Loop, eigenes State-Enum (`.needsCredentials`/`.needsSignIn`/`.loading`/`.ready`/`.error`, ggf. ohne `.rateLimited`, da kein festes Kontingent bekannt ist). Ein Fehler auf der Wärmepumpen-Seite darf die PV-Seite nie beeinträchtigen und umgekehrt — exakt das Muster, für das `ContentView`/`BACKLOG.md` die PV-Architektur bereits vorbereitet haben.
- **Auth: OAuth2 mit PKCE**, nur eine Client-ID nötig (kein Secret, kein API-Key wie bei Enphase). Login-Flow analog zu Enphase über `WebAuthenticationSession` mit Custom-URL-Scheme-Redirect.
- **Falle (explizit aus der Praxis bekannt):** Das Gateway (z. B. Vitoconnect) erscheint in der Geräteliste als eigenständiges Pseudogerät und liefert nur Netzwerk-Features, nicht die Heizungsdaten. Die Geräteauswahl nach dem Login muss das **richtige** Device (`deviceId`, i. d. R. `"0"`) explizit identifizieren, nicht einfach das erste Listenelement nehmen. Falls mehrere Installationen/Gateways/Geräte existieren, braucht es eine (ggf. einmalige) Auswahl in den Einstellungen.
- **Poll-Takt:** kein festes Monatskontingent wie bei Enphase bekannt; 5–15 Minuten gelten als sicher, im Referenzprojekt 10 Minuten produktiv. Kein Bedarf für ein `EnphaseRequestBudget`-Äquivalent — ein einfacher fester Intervall-Timer reicht, perspektivisch mit Backoff bei Fehlern.
- **Server-seitige Aggregate nutzen statt selbst zu rechnen:** Für Verbrauch/Erzeugung/Effizienz die `.summary.*`- und `.scop`/`.spf`-Werte direkt anzeigen. Das erspart der Wärmepumpen-Seite die aufwendige Backfill-/Finalize-/Pruning-Maschinerie, die für Enphase nötig war (siehe Abschnitt 5).
- **Reine Fachlogik-Typen ohne UI-Abhängigkeit**, wo sinnvoll (z. B. ein `PressureAlertEvaluator` analog zu `PressureAlertTracker`), damit Kernlogik wie bei Enphase ohne UI testbar bleibt.
- **Gemeinsame, wiederverwendbare UI-Bausteine statt Kopien**: `MetricCard`/`BatteryCard` existieren aktuell als `private struct` in `SolarView.swift` und müssen vor der Wärmepumpen-UI in eigene, von beiden Quellen nutzbare Dateien verschoben werden (siehe Abschnitt 6).
- **Zweite, klar unterscheidbare Akzentfarbe** für die Wärmepumpe, wie in `BACKLOG.md` bereits gefordert — Vorschlag: PV bleibt bei der bestehenden Orange-/Sonnen-Metapher, Wärmepumpe bekommt z. B. ein Indigo-/Violett-Ton (bewusst *nicht* Rot/Blau, da diese Farben in den bestehenden PV-Kacheln bereits für Verbrauch/Batterie/Einspeisung belegt sind). Endgültige Farbwahl ist eine spätere UI-Detailentscheidung, kein Blocker für diesen Plan.

## 4. Navigationsstruktur (Home → Übersicht → Detail)

`ContentView` ist aktuell eine `TabView` mit genau einem Tab ("PV-Anlage"), bewusst so angelegt, dass weitere Tabs ergänzt werden können. Vorschlag für die neue Struktur:

```
TabView
├── Tab "Start"        (home-Icon)      → HomeView: kombinierte KPIs aus PV + Wärmepumpe
├── Tab "PV-Anlage"     (sun.max.fill)  → SolarOverviewView (heutige SolarView-Wurzel)
│     └── NavigationStack-Detailmasken: Verlauf (bestehend), Einstellungen (bestehend)
└── Tab "Wärmepumpe"    (noch zu wählendes SF Symbol, z. B. "heater.vertical.fill")
      → HeatPumpOverviewView
      └── NavigationStack-Detailmasken: Heizkreise, Warmwasser, Effizienz & Verbrauch,
          Verdichter/Kältekreis (Diagnose), Anlagendruck, Einstellungen
```

Einordnung gegenüber der bestehenden PV-Struktur: Die heutigen Screens `PVHistoryScreen` ("Verlauf") und `PVSettingsScreen` ("Einstellungen"), die bislang über ein Toolbar-Menü erreichbar sind, werden konzeptionell zu den ersten beiden **PV-Detailmasken** — die bestehende Navigation ändert sich technisch kaum, bekommt aber eine klarere begriffliche Einordnung (Übersicht vs. Detail), die auch für die Wärmepumpe gilt.

Der **Home-Bildschirm** ist bewusst ein eigener dritter Tab (nicht die Startansicht *innerhalb* eines Tabs), damit er unabhängig von PV/Wärmepumpe existiert und nicht einer der beiden Quellen "gehört". Er zeigt kompakte KPI-Kacheln beider Seiten (z. B. PV-Erzeugung/Autarkie/Batterie-SOC und Wärmepumpen-Außentemperatur/Warmwassertemperatur/aktuelle elektrische Leistung) und verlinkt bei Bedarf per Tab-Wechsel in die jeweilige Übersicht. Eine inhaltliche Verrechnung beider Quellen (z. B. "PV-Überschuss deckt X % des Wärmepumpenverbrauchs") ist **nicht** Teil dieses Plans — das würde die bewusste Entkopplung der beiden Models aufweichen und ist allenfalls ein späterer, eigenständiger Epic.

Offene Frage, ob "Start" der erste oder letzte Tab sein soll: Vorschlag ist **erster Tab**, da es der in der Anforderung beschriebene Einstiegspunkt beim App-Start ist (`TabView` zeigt standardmäßig den ersten Tab).

## 5. Datenmodell

Im Unterschied zu Enphase braucht die Wärmepumpen-Seite voraussichtlich **deutlich weniger eigene Persistenz**, weil Viessmann die relevanten Zeiträume bereits vorberechnet liefert:

- **Live-/Momentanwerte** (Temperaturen, Drücke, Verdichterstatus, Betriebsmodi): nur im `HeatPumpModel` im Speicher gehalten, keine SwiftData-Persistenz nötig — analog zu "heute"-Werten, aber ohne den Finalisierungs-Mechanismus, den Enphase wegen nachlaufender Nullen brauchte.
- **Effizienz-/Verbrauchs-Fenster** (`currentDay`/`currentMonth`/`currentYear`/`lastMonth`/`lastSevenDays`/`lastYear`, SCOP/SPF): direkt aus der API übernehmen und anzeigen, keine eigene Aggregation wie `PVPeriodAggregation` nötig. Optionale spätere Erweiterung: eigene Tagessnapshots speichern, falls Verläufe über die gelieferten Fenster hinaus gewünscht sind (siehe Abschnitt 7, spätere Phase).
- **Settings/Secrets**: `ViessmannSettings` + `ViessmannKeychainStore`, analog zu `EnphaseSettings`/`EnphaseKeychainStore`, aber schlanker (nur Client-ID statt Client-ID/Secret/API-Key), zusätzlich Installation-/Gateway-/Geräte-ID nach der expliziten Geräteauswahl.
- **Kein eigener `EnphaseRequestBudget`/`EnphaseRequestThrottle`-Gegenpart nötig**, da kein festes monatliches Kontingent bekannt ist (siehe Abschnitt 3) — ein einfacher Intervall-Poll reicht.

Für SwiftData-Änderungen gilt die bereits in `ERKENNTNISSE_MACOS.md` dokumentierte Falle: neue nicht-optionale `@Model`-Properties brauchen ihren Default direkt an der Deklaration, sonst bricht die Lightweight-Migration. Das bestehende Backlog-Item F8.1 (echter `VersionedSchema`/`SchemaMigrationPlan`) sollte idealerweise **vor** oder **mit** der ersten Wärmepumpen-Schemaänderung angegangen werden, statt es weiter aufzuschieben. **Update 2026-10-06:** F8.1 ist umgesetzt (`EnergieSchemaV1`/`EnergieMigrationPlan` in `Model/EnergieSchema.swift`) — eine Wärmepumpen-Schemaänderung legt dort `EnergieSchemaV2` an.

## 6. Nötige Vorarbeiten (Refactoring, bevor die Wärmepumpen-UI entsteht)

- `MetricCard` und `BatteryCard` aus `SolarView.swift` (aktuell `private struct`) in eigene, quellenunabhängige Dateien verschieben (z. B. `Energie/UI/MetricCard.swift`), damit sie von PV- und Wärmepumpen-Screens gleichermaßen genutzt werden können, ohne Code zu duplizieren.
- Begriffliche Umbenennung/Neuordnung der bestehenden PV-Screens als "Übersicht" + "Detailmasken" (siehe Abschnitt 4) — voraussichtlich nur Kommentare/Struktur, kaum funktionale Änderung.
- Neue Akzentfarbe(n) für die Wärmepumpe definieren (siehe Abschnitt 3).

## 7. Phasenplan (Epics)

Reihenfolge so gewählt, dass nach jeder Phase ein funktionsfähiger Zwischenstand existiert (passend zum etablierten "ein Feature/Fix pro Branch, nichts ohne Freigabe mergen"-Vorgehen):

1. **HP-0 — Gemeinsame UI-Bausteine extrahieren** (Abschnitt 6), ohne fachliche Änderung. Risikoarmer Einstieg, Voraussetzung für alles Weitere.
2. **HP-1 — Viessmann-Authentifizierung**: PKCE-OAuth-Client, `ViessmannKeychainStore`/`ViessmannSettings`, Login-Flow, explizite Geräteauswahl (Schutz vor dem Gateway-Pseudogerät).
3. **HP-2 — `HeatPumpModel` + Live-Abruf** der wichtigsten Momentanwerte (Außentemp., Vorlauf/Rücklauf, Warmwassertemp., aktuelle elektrische Leistung/Wärmeleistung, Verdichterstatus), eigener Poll-Loop (~10 Min).
4. **HP-3 — Wärmepumpen-Übersichtsmaske** (neuer Tab, Root-View mit KPI-Kacheln, wiederverwendete `MetricCard`).
5. **HP-4 — Detailmasken**, voraussichtlich in dieser Reihenfolge:
   - Heizkreise (Temperaturen, Modus/Programm, Heizkurve)
   - Warmwasser (Speichertemperatur, Modus, Zirkulation)
   - Effizienz & Verbrauch (SCOP/SPF, `.summary.*`-Fenster als Kacheln/Diagramme)
   - Anlagendruck (inkl. Alarmschwellen, Wiederverwendung der bestehenden lokalen-Benachrichtigungs-Infrastruktur aus Epic 5)
   - Verdichter/Kältekreis (technische Diagnoseansicht, niedrigere Priorität)
   - Einstellungen (Zugangsdaten, Geräteauswahl, Abmelden — analog `PVSettingsScreen`)
6. **HP-5 — Zentraler Home-Bildschirm**: neuer erster Tab, kombinierte KPI-Kacheln aus `SolarModel` und `HeatPumpModel`, `ContentView`-Umbau auf drei Tabs.

Spätere, nicht in diesem Plan verbindlich festgelegte Ausbaustufen:

7. **HP-6 (später) — Anlagendruck-Benachrichtigungen**, analog zu den bestehenden PV-Benachrichtigungen (F5.5).
8. **HP-7 (später) — Eigene Verlaufsspeicherung**, falls die serverseitigen Aggregatfenster (`lastYear` etc.) für Diagramme nicht ausreichen.
9. **HP-8 (später) — Widget-Erweiterung**: Home-Screen-Widget um Wärmepumpen-Kachel oder kombinierte Kachel ergänzen. Nicht Teil der aktuellen Anforderung, die sich nur auf In-App-Bildschirme bezieht.

## 8. Offene Fragen (vor oder während der Umsetzung zu klären)

- Liegen bereits eine Viessmann-Client-ID und Zugangsdaten vor (analog zum bereits vorhandenen Enphase-Developer-Zugang), oder muss das zuerst eingerichtet werden?
- Gibt es mehr als eine Installation/ein Gateway/ein Gerät im Viessmann-Account, oder ist die Geräteauswahl in der Praxis trivial (immer genau ein Gerät)?
- Sollen die KPI-Kacheln auf dem Home-Bildschirm fest vorgegeben sein, oder (wie bei den PV-Wertreihen, F3.5) vom Nutzer auswählbar?
- Soll die Detailmaske "Verdichter/Kältekreis" (stark technische Werte) überhaupt für den Alltagsgebrauch sichtbar sein, oder eher ausgeblendet/optional ("Diagnose"-Bereich)?
- Reicht ein einfacher Intervall-Poll für die Wärmepumpe, oder soll von Anfang an ein Backoff-/Fehlerzähler-Mechanismus wie bei Enphase vorgesehen werden, falls sich doch ein praktisches Rate-Limit zeigt?

## 9. Abgrenzung

Nicht Teil dieses Plans: Verrechnung/Korrelation von PV- und Wärmepumpendaten (z. B. Eigenverbrauchsoptimierung), Widget-Erweiterung, Push-Benachrichtigungen (ohnehin für den kostenlosen Apple-Developer-Account blockiert, siehe `BACKLOG.md`), CloudKit-Synchronisation der Wärmepumpendaten (aus denselben, bereits für PV dokumentierten Gründen aktuell nicht möglich).
