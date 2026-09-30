# Backlog — PV-Anlage (Enphase) in der iOS-App "Energie"

Sammlung aller Anforderungen/Features, bevor mit der Umsetzung begonnen wird. Quellen: `ENPHASE_API_WERTE.md` (API-Referenz), `ENPHASE_INTEGRATION_SPEC.md` (Architekturentwurf der PV-Integration) und `ERKENNTNISSE_MACOS.md` (Erfahrungsbericht aus dem gesamten macOS-Schwesterprojekt, inkl. Viessmann-Wärmepumpe) — alle drei ursprünglich für ein **separates macOS-Projekt** geschrieben. macOS-/Wärmepumpen-spezifische Teile (Sidebar/MenuBarExtra, `DashboardModel`, Sandbox-Abwägungen, NSImage-Icons, AppleScript-Benachrichtigungen) sind hier **nicht** übernommen — nur Enphase-API-Fakten, datenseitige Architektur und übertragbare Engineering-Lektionen wurden extrahiert und für iOS neu bewertet.

Status aller Einträge: **Backlog**, außer wo unten als umgesetzt markiert.

## Umsetzungsstand

- **✅ Branch `feature/enphase-pv-basis` (2026-09-30, noch nicht gemergt):** Erster dünner Ende-zu-Ende-Slice. OAuth2-Login (F1.1, via `WebAuthenticationSession`, kein Info.plist-Eintrag nötig), Zugangsdaten-Verwaltung (F1.2) und lokale Keychain-Speicherung (F1.3, bewusst **nicht** iCloud-synchronisiert, siehe Epic-0-Rückstellung), Token-Refresh (F1.4), Systemerkennung (F1.5), Momentanwerte-Kennzahlenkarten inkl. Autarkiegrad/Speicherzustand/geschätzter Vergütung (F2.1–F2.3), ein lokales `PVDailySample`-Modell mit Default-Werten an der Deklaration (F3.1/F8.2-Lektion von Anfang an beachtet) und eine minimale Minuten-Drossel als Sicherheitsnetz (F4.1-light, 75s/10 Requests — volles Monatsbudget-Management F4.2–F4.4 folgt separat). Noch **nicht** enthalten: Backfill (F3.2), täglicher Abschluss-Durchlauf (F3.3), Diagramme (F3.4/F3.5), Pruning (F3.6), Widget (F5.4/F5.6), Benachrichtigungen (F5.5), Einstellungen-Screen für Tarif (F6.2 — aktuell als Konstante 0,08 €/kWh hartkodiert). Token-Antwortformat gegen Enphase noch nicht mit echten Zugangsdaten verifiziert (siehe "Bekannte Unsicherheiten" unten).

## Zusammenarbeits-Konventionen (aus `ERKENNTNISSE_MACOS.md` übernommen, 2026-09-30)

- Jedes Feature auf einem eigenen `feature/<name>`-Branch, jeder Fix auf `fix/<beschreibung>`, Releases auf `release/v<major>.<minor>`.
- **Nach jedem abgeschlossenen Arbeitsschritt sofort committen und pushen** (auf dem jeweiligen Feature-/Fix-Branch) — nicht erst am Ende einer größeren Aufgabe sammeln.
- `git merge` nach `main` **und** das Löschen von Branches nur nach expliziter Freigabe/Anweisung des Nutzers, nie eigenständig. `release/*`-Branches werden nie gelöscht, außer ausdrücklich namentlich genannt.
- Release-Ablauf und Export-Methode: siehe Memory bzw. bei Bedarf gesondert klären — die Export-Methode der macOS-Vorlage (kein Entwicklerteam/Zertifikat) ist für eine App-Store-/Geräte-taugliche iOS-App **nicht** übertragbar.

## Design-Leitplanke (gilt für jede UI in diesem Projekt)

**Die UI soll durchgängig professionell, modern und freundlich wirken** — kein Rohdaten-/Debug-Look, sondern ein Dashboard, dem man ansieht, dass es sorgfältig gestaltet ist (klare Typografie/Hierarchie, durchdachte Farbgebung für Kennzahlen/Status, ruhige statt überladene Ansichten, konsistente Abstände/Komponenten). Gilt für App, Einstellungen **und** Widget gleichermaßen. Bei jedem UI-Feature (F1.2, F2.x, F3.4, F5.4 …) verbindlich mitzudenken, nicht nur "es funktioniert".

## Zukünftige zweite Energiequelle: Wärmepumpe (konkret, nicht mehr nur hypothetisch)

Ergänzung vom 2026-09-30: Die in F5.3 bereits angelegte Erweiterbarkeit für "eine zweite Energiequelle" ist **konkret die Wärmepumpe** (wie im macOS-Schwesterprojekt: Viessmann IoT API neben Enphase-PV, siehe `ERKENNTNISSE_MACOS.md`). Das beeinflusst das UI-Design schon jetzt, auch wenn die Wärmepumpe noch nicht umgesetzt wird:

- **Navigation von Anfang an mehrsektions-tauglich anlegen** (z. B. `TabView` mit "PV-Anlage" als erstem Tab), statt einer Einzelansicht, die später komplett umgebaut werden müsste, wenn ein zweiter Tab "Wärmepumpe" dazukommt.
- **Gemeinsame, wiederverwendbare UI-Bausteine** für Kennzahlenkarten/Diagramme (analog `DetailCard`/`InfoRow`/`formattedMeasurement` aus der macOS-Vorlage) statt PV-spezifischer Einzellösungen — spart beim zweiten Datenquellen-Screen doppelte Arbeit und sichert einen konsistenten Look zwischen beiden Bereichen.
- **Farbgebung/Iconografie so wählen, dass sie sich für eine zweite Kategorie erweitern lässt** (z. B. PV in einer Akzentfarbe, Wärmepumpe später in einer klar unterscheidbaren zweiten Akzentfarbe), statt PV die einzige/globale Markenfarbe der App zu geben.
- Datenseitig bleibt es beim bereits beschlossenen Muster aus [[project_pv_enphase_integration]]/F1.5-Notiz: eigenes Model pro Quelle, unabhängiger Poll-/State-Loop — UI-seitig heißt das: eigener Screen/Tab pro Quelle, keine gemeinsame "Universal-Ansicht" für beide.

## Entscheidungen (aus Rückfragen vom 2026-09-30)

- **Aktualität/Hintergrund:** Zusätzlich zur App ein **Home-Screen-Widget** mit eigener Timeline-Policy (siehe F5.4, jetzt fest eingeplant statt optional). Daraus folgt eine wichtige technische Konsequenz: siehe F5.6.
- **Enphase-Zugang:** Client-ID/Client-Secret/API-Key sind bereits im Enphase-Entwicklerportal angelegt — F1.2 kann direkt gegen echte Zugangsdaten getestet werden, sobald die Redirect-URI dort hinterlegt ist.
- **Scope:** Reines PV-Monitoring für jetzt, aber Datenmodell/Navigation sollen so angelegt werden, dass eine zweite Energiequelle später ohne größeren Umbau ergänzt werden kann (siehe F5.3).
- **Zielplattform:** iPhone primär, iPad-Layout wird mitgedacht, plus Widget-Extension als eigenes Target. **Mindest-iOS-Version: iOS 27.**
- **Widget-Architektur (F5.6) konkretisiert:** Die Widget-Extension pollt über ihren eigenen `TimelineProvider` selbst — das ist der einzige Ort, der im Hintergrund läuft, wenn die App geschlossen ist (die App selbst kann/soll das nicht, iOS suspendiert normale Apps im Hintergrund). Ergebnis + Budget-Zähler landen im App-Group-Speicher; die Haupt-App liest beim Öffnen nur daraus und darf optional sofort selbst nachpollen, wenn Budget übrig ist. Kein zusätzlicher `BGAppRefreshTask` nötig — eine Stelle pollt, nicht zwei. **Update 2026-09-30:** Ob die App-Groups-Capability unter dem gewählten kostenlosen Personal Team überhaupt nutzbar ist, ist unklar (siehe Kapitel "Nicht umsetzbar ohne kostenpflichtigen Apple Developer Account") — in Xcode zu verifizieren, sobald F5.4 ansteht.
- **Cloud-Speicherung (Epic 0) zurückgestellt, lokal-only für jetzt:** Kein bezahlter Apple-Account → CloudKit entfällt. App speichert vorerst rein lokal pro Gerät; Secrets/Tokens bleiben in einem **lokalen** Keychain-Item (nicht iCloud-synchronisiert). Details siehe Kapitel "Nicht umsetzbar ohne kostenpflichtigen Apple Developer Account".
- **Startpunkt der Umsetzung:** Dünner Ende-zu-Ende-Slice zuerst — erster Branch: lokales SwiftData-Grundgerüst (statt CloudKit, siehe oben) + OAuth-Login (Epic 1) + eine einzige Ansicht mit echten Momentanwerten (Teil von Epic 2), um früh etwas Lauffähiges gegen die echte Anlage zu sehen. Rest (Historie, Diagramme, Widget, Benachrichtigungen) folgt danach Epic für Epic.

## Nicht umsetzbar ohne kostenpflichtigen Apple Developer Account

Entscheidung des Nutzers (2026-09-30): **kein** kostenpflichtiges Apple Developer Program-Konto (99 €/Jahr). Das macht folgende, bereits geplante Punkte **in der aktuell beschriebenen Form nicht umsetzbar** — ein kostenloses "Personal Team" in Xcode kann die dafür nötigen Capabilities nicht aktivieren:

- **Gesamtes Epic 0 (CloudKit-Cloud-Synchronisation), sicher blockiert.** F0.1–F0.4 setzen direkt auf einen privaten CloudKit-Container auf. CloudKit ist laut Apple ausdrücklich Program-Mitgliedern vorbehalten — ohne Mitgliedschaft lässt sich die iCloud/CloudKit-Capability in Xcode für dieses Projekt gar nicht erst hinzufügen. Betrifft direkt: SwiftData+CloudKit-Persistenz (F0.1), CloudKit-Datenmodell-Constraints (F0.2), Poll-Koordination über einen CloudKit-Record (F0.4).
- **F0.3 iCloud-Keychain-Synchronisation von Secrets/Tokens, sehr wahrscheinlich blockiert.** Synchronisierbare Keychain-Items hängen an derselben iCloud-Kontoinfrastruktur wie CloudKit — mit hoher Wahrscheinlichkeit ebenso betroffen, in Xcode beim konkreten Einrichten zu verifizieren.
- **Geräteübergreifende Push-Benachrichtigungen, sicher blockiert.** Eine Erweiterung von F5.5 auf Cross-Device-Alarme per Remote-/Silent-Push (APNs) ist ohne Program-Mitgliedschaft nicht möglich. **Lokale** Benachrichtigungen auf demselben Gerät, das die Bedingung erkannt hat, sind davon **nicht** betroffen und bleiben kostenlos nutzbar.
- **F5.4/F5.6 Widget-Extension mit App-Group-Datenaustausch — Status unklar.** Ob die App-Groups-Capability unter einem kostenlosen Personal Team nutzbar ist, hat sich bei Apple mehrfach geändert und lässt sich über die Standard-Doku nicht eindeutig klären. Muss beim tatsächlichen Einrichten in Xcode direkt geprüft werden (Xcode meldet sofort einen Fehler, falls die Capability für das Team gesperrt ist). Falls blockiert: Das Widget könnte dann keine mit der App geteilten Daten lesen/schreiben — es müsste entweder komplett eigenständig arbeiten (eigener, redundanter Enphase-Zugriff samt eigener Budget-Buchführung, was das Rate-Limit-Risiko aus Epic 4 erhöht) oder auf Live-Daten verzichten und nur statische/seltene Inhalte zeigen.
- **Praktische Einschränkung unabhängig von einzelnen Capabilities:** Mit einem kostenlosen Personal Team laufen selbst signierte Apps nur **7 Tage**, bevor sie über Xcode neu installiert werden müssen (Ablauf des kostenlosen Provisioning-Profils) — relevant für eine App, die dauerhaft aktuelle Anlagenwerte zeigen soll. Außerdem keine TestFlight-/App-Store-Distribution, nur Installation über direkt an Xcode angeschlossene, registrierte Geräte.

**Konsequenz (entschieden 2026-09-30): Cloud-Anforderung vorerst zurückgestellt.** Statt einer der Alternativen (eigener Server, Managed-Backend-Dienst) zu wählen, speichert die App **zunächst rein lokal pro Gerät** (normales `SwiftData` ohne CloudKit). Die zentrale Cloud-Speicherung bleibt ein **späteres Muss**, nicht Teil der jetzt startenden Umsetzung — wird nachgeholt, sobald eine Backend-Entscheidung ansteht (bezahlter Apple-Account für CloudKit, oder ein Managed-Dienst/eigener Server). Bis dahin: **kein** geräteübergreifender Datenzugriff, die geplante macOS-App kann vorerst nicht auf denselben Datenbestand zugreifen wie die iOS-App — auch das ist zurückgestellt.

## Epic 0 — Cloud-Synchronisation (CloudKit) — ZURÜCKGESTELLT (blockiert ohne kostenpflichtigen Apple Developer Account, siehe Kapitel oben). Inhalt bleibt als Referenz/Blaupause stehen, für den Fall, dass die Cloud-Anforderung später doch mit CloudKit umgesetzt wird.

Ursprüngliche Anforderung vom 2026-09-30: Die Daten sollten zentral in der Cloud gespeichert werden, nicht nur lokal auf dem Gerät. Erste Entscheidung war **Apple CloudKit** (private Datenbank) — seitdem durch die Absage an einen bezahlten Account **verworfen** (siehe oben). Die folgenden Punkte (F0.1–F0.6) beschreiben, wie es mit CloudKit gegangen wäre, und dienen als Grundlage, falls die Entscheidung revidiert wird.

- **F0.1 SwiftData + CloudKit statt reinem lokalen `ModelConfiguration`.** `ModelContainer` mit privater CloudKit-Datenbank konfigurieren (eigener iCloud-Container, z. B. `iCloud.de.florian.tobias.Energie`). Gilt für `PVDailySample` und alle weiteren Modelle von Anfang an — nachträglich einzuführen ist deutlich teurer als von Beginn an.
- **F0.2 Harte CloudKit-Constraints für `@Model`-Typen beachten** (verschärft die bereits in F8.2 dokumentierte Falle zu einer **Pflicht**, nicht nur einer Empfehlung): Jedes Property braucht einen Default **an der Deklaration**; `@Attribute(.unique)` wird von CloudKit-Sync **nicht unterstützt** (muss entfernt/vermieden werden); Relationships müssen optional sein. Vor Epic 3/8-Implementierung gegen die aktuelle SwiftData-CloudKit-Doku (iOS 27) verifizieren, da sich Details ändern können.
- **F0.3 Secrets/Tokens geräteübergreifend über iCloud Keychain teilen.** Client-ID/Secret/API-Key sowie das OAuth-Token-Paar (Access-/Refresh-Token) als synchronisierbares Keychain-Item (`kSecAttrSynchronizable`/iCloud-Keychain) statt nur lokal — **ein** Login auf einem Gerät genügt, alle Geräte (inkl. künftiger Mac) nutzen dasselbe Token-Paar, statt sich gegenseitig mit unabhängigen Refresh-Zyklen in die Quere zu kommen.
- **F0.4 Poll-Koordination über CloudKit statt (nur) lokaler App Group.** Ersetzt/erweitert F5.6: Das bisherige Modell "nur die Widget-Extension pollt lokal" reicht nicht mehr, sobald mehrere Geräte (iPhone, iPad, Mac) potenziell alle pollen könnten. Monatsbudget-Zähler und "letzter Poll"-Zeitstempel (Epic 4) werden als CloudKit-Record geführt, den jedes Gerät vor einem Poll-Versuch prüft. Echte verteilte Sperren sind bei diesen Größenordnungen (max. 10 Abfragen/Minute, Poll-Intervall ≥15 Min) nicht nötig — ein gelegentlicher, seltener Doppel-Poll zweier Geräte im selben Intervall ist ein akzeptables Restrisiko, kein Show-Stopper.
- **F0.5 Voraussetzung: Apple-Developer-Account mit iCloud-Capability.** CloudKit-Container muss im Apple-Developer-Portal/Xcode-Capabilities angelegt werden (manueller Schritt, wie schon die Enphase-Redirect-URI).
- **F0.6 Tests bleiben lokal.** Für Unit-Tests weiterhin eine rein lokale, In-Memory-`ModelConfiguration` verwenden (kein echter CloudKit-Zugriff in Tests) — konsistent mit der bereits beschlossenen DI-Konvention (Epic "Engineering-Konventionen").

## Epic 1 — Enphase-Authentifizierung

- **F1.1 OAuth2-Login-Flow.** Authorization-Code-Flow über `ASWebAuthenticationSession`, Rücksprung per Custom-URL-Scheme (`…://enphase-oauth-callback` o.ä.), im Enphase-Portal vom Nutzer manuell hinterlegt.
- **F1.2 Zugangsdaten-Verwaltung.** Eingabe von Client-ID, Client-Secret, API-Key in einer Einstellungen-/Login-Ansicht.
- **F1.3 Sichere Speicherung von Secrets & Tokens.** ⚠️ Abweichung von der Spec-Vorlage: Dort lagen Client-Secret/Tokens bewusst im Klartext in `UserDefaults` (Begründung: rein lokales macOS-Tool, Sandbox ohnehin deaktiviert). Für iOS: **lokales** Keychain-Item (`kSecClassGenericPassword`) für Client-Secret, API-Key, Access-/Refresh-Token. (Ursprünglich war geräteübergreifende iCloud-Keychain-Synchronisation geplant, siehe F0.3 — durch die Absage an einen bezahlten Apple-Account zurückgestellt.)
- **F1.4 Token-Refresh.** Automatischer Refresh vor Ablauf; Format der Token-Antwort (`access_token`/`refresh_token`/`expires_in`) laut Doku unverifiziert — beim ersten echten Login verifizieren und ggf. `ENPHASE_API_WERTE.md` nachführen.
- **F1.5 Systemerkennung.** `GET /systems` einmalig abfragen, `system_id` cachen. Mehrfachanlagen: laut Spec-Vorlage nicht unterstützt (erstes System wird automatisch übernommen) — zu bestätigen.

> **Übertragbares Architekturmuster (aus `ERKENNTNISSE_MACOS.md`):** Im macOS-Projekt hat jede Datenquelle (Viessmann-Wärmepumpe, Enphase-PV) ihr eigenes `Model` mit eigenem OAuth-Client, eigenem Poll-Loop und eigenem State-Enum — komplett unabhängig, ein Fehler/Rate-Limit auf der einen Seite betrifft die andere nie. Da wir die PV-Architektur bewusst so anlegen, dass später eine zweite Energiequelle ergänzbar ist (siehe Entscheidungen oben, F5.3), übernehmen wir dieses Muster von Anfang an: ein eigenständiges `SolarModel`-Äquivalent statt eines generischen "DashboardModel", das später mühsam aufgespalten werden müsste.

## Epic 2 — Live-/Tageskennzahlen

- **F2.1 Kennzahlenkarten:** Autarkiegrad (%, berechnet: `(Verbrauch − Netzbezug) / Verbrauch`), Verbrauch (kWh), Produktion (kWh), Einspeisung (kWh) — jeweils "heute".
- **F2.2 Speicherzustand-Karte:** Ladezustand (%), heute geladen/entladen (kWh) — nur relevant, da eine Encharge-Batterie vorhanden ist.
- **F2.3 Geschätzte Einspeisevergütung.** Konfigurierbarer Tarif (Default-Vorschlag 0,08 €/kWh, Richtwert ohne Abrechnungsanspruch) × Einspeisung, als Zusatztext bei der Einspeisung-Karte.

## Epic 3 — Historische Daten & Diagramme

- **F3.1 Lokale Tageshistorie.** Eigenes Datenmodell (analog `PVDailySample`: Datum, produzierte/verbrauchte/importierte/exportierte Wh, Batterie-SOC/Lade-/Entladewerte, `isFinal`-Flag).
- **F3.2 Rückwirkendes Nachladen (Backfill).** Fehlende Tage über die fünf `_lifetime`-Endpunkte nachladen; Zeitraum ab Inbetriebnahmedatum (`operational_at`) statt fixem 30-Tage-Fenster (Fallback 30 Tage, falls `operational_at` fehlt).
- **F3.3 Täglicher Abschluss-Durchlauf.** Live-gepollte, nicht-finale Tageswerte werden einmal täglich durch die finalen `_lifetime`-Werte ersetzt; nachlaufende Nullen ("noch nicht gemeldet") werden nicht übernommen, Tag bleibt nicht-final.
- **F3.4 Diagramme:** Balkendiagramme für Tage (letzte 30), letzte 12 Monate, Jahre (lokal aus Tageswerten aggregiert, keine zusätzlichen API-Abfragen).
- **F3.5 Wertreihen-Auswahl.** Umschalter Alle/Produktion/Verbrauch/Einspeisung, gemeinsam für alle Diagramme.
- **F3.6 Datenaufbewahrung/Pruning.** Muster aus `ERKENNTNISSE_MACOS.md`: nicht alles unbegrenzt behalten. Rohe Poll-Snapshots auf die letzten paar Einträge begrenzen; Tageswerte, die älter als ein Jahr sind, zu Jahressummen aggregieren und die Tageszeilen danach löschen (analog `SolarModel.pruneOldDailySamplesIfNeeded`/`PVYearlySample` in der Vorlage). Verhindert unbegrenztes Datenbankwachstum bei mehrjähriger Nutzung.

**Implementierungshinweis Diagramme (F3.4), übertragbare, getestete Swift-Charts-Muster aus der Vorlage** (vor Umsetzung gegen die zu diesem Zeitpunkt aktuelle Swift-Charts-API auf iOS 27 verifizieren, falls es neuere APIs gibt):
- Gruppierte Balken über mehrere Kalendereinheiten: `BarMark`/`PointMark` mit `PlottableValue.value(_:_:unit:calendar:)` statt einem `start..<end`-Intervall, dazu `.position(by:)` für saubere Gruppierung und kalenderbewusste Achsenbeschriftung.
- Falle: Mehrere `LineMark`s ohne unterscheidendes `by:`-Attribut verschmelzen zu einer Linie, `.annotation()` erscheint dann nur am ersten Mark — für Pro-Punkt-Beschriftungen zusätzliche `PointMark`s verwenden.
- Zweite Y-Achse simulieren: Werte in den bestehenden Wertebereich hochskalieren, zweite `AxisMarks(position: .trailing)` mit eigener Beschriftung (Swift Charts hat keine echte zweite Y-Domain).

## Epic 4 — API-Budget-Management

Enphase begrenzt **pro Minute und pro Monat** (laut `ENPHASE_API_WERTE.md`; die konkreten Plan-Kontingente stehen nicht in der Spec — in der Vorlage wurden 10/Minute und 1000/Monat als vom Nutzer vorgegebene Annahme verwendet, nicht offiziell verifiziert).

- **F4.1 Minuten-Drossel.** Gleitendes Fenster vor jeder Abfrage. Laut `ERKENNTNISSE_MACOS.md` bewusst **75 Sekunden statt 60** angesetzt — Sicherheitspuffer über der tatsächlichen 60s-Grenze, hat sich in der Vorlage bewährt.
- **F4.2 Monatsbudget.** Persistenter Zähler pro Kalendermonat, adaptives Poll-Intervall statt fixem Takt (nie schneller als 15 Minuten), Reserve für den täglichen Abschluss-Durchlauf. Bei fast aufgebrauchtem Monatsbudget ergibt das in der Vorlage grob nur noch alle 4–5 Stunden einen Live-Abruf. Persistierter Zeitpunkt des letzten Polls verhindert einen sofortigen Extra-Poll bei jedem App-/Widget-Neustart.
- **F4.3 429-Handling.** Antwort-Body (`period`, `period_start`, `period_end`) auswerten statt nur generischem `Retry-After`.
- **F4.4 Transparenzanzeige.** "Abfragen diesen Monat: X / Limit · nächster Abruf ca. HH:MM" in den Einstellungen.

## Epic 5 — iOS-spezifische Architektur (neu, in der macOS-Spec nicht adressiert)

Die macOS-Vorlage geht von einem dauerhaft laufenden Task-Loop (`Task { while true { … } }`) aus, der im Hintergrund weiterläuft, solange die Mac-App offen ist. **Das funktioniert auf iOS so nicht** — Apps werden im Hintergrund suspendiert. Das ist der wichtigste architektonische Punkt, den ich vor der Umsetzung mit dir klären möchte (siehe Rückfragen unten).

- **F5.1 Aktualisierungsstrategie festlegen:** Optionen sind (a) nur Refresh beim App-Start/Vordergrund (einfachste Lösung, aber "heute"-Werte können veralten), (b) `BGAppRefreshTask` für gelegentliche Hintergrund-Updates (vom System terminiert/gedrosselt, kein festes Intervall garantiert), (c) Widget mit eigenem Refresh-Timeline (unabhängig von der App).
- **F5.2 Secrets in Keychain** statt UserDefaults (siehe F1.3).
- **F5.3 Eigene iOS-Navigation**, so angelegt, dass eine zweite Energiequelle später ergänzbar ist, ohne die PV-Ansicht umzubauen — z. B. eigenes Model pro Quelle (wie in der macOS-Vorlage `SolarModel` getrennt von `DashboardModel`) und eine Navigationsstruktur (`TabView`), die auch mit nur einem Tab sinnvoll aussieht.
- **F5.4 Home-Screen-Widget** via WidgetKit: Momentanwerte (Produktion/Autarkiegrad) ohne App-Start sichtbar. **Fest eingeplant** (siehe Entscheidungen oben).
- **F5.5 (Vorschlag) Lokale Benachrichtigungen** bei Anlagenausfall, erschöpftem Monatsbudget oder niedrigem Speicherstand.
- **F5.6 Geteilter Speicher für App + Widget (App Group) — wieder aktuell, da Epic 0/CloudKit zurückgestellt.** Enphase begrenzt hart auf ~10 Abfragen/Minute und ~1000/Monat (Epic 4) — App **und** Widget dürfen nicht unabhängig voneinander pollen, sonst wird das Budget doppelt verbraucht. Lösung (nur ein Gerät, kein Multi-Device-Sync solange Cloud zurückgestellt ist): Die **Widget-Extension** pollt über ihren `TimelineProvider` (läuft auch bei geschlossener App), schreibt Ergebnis + Budget-Zähler in einen **App-Group-Container**; die App liest beim Öffnen nur daraus und darf optional sofort selbst nachpollen, wenn Budget übrig ist. **Offen:** ob App Groups unter dem kostenlosen Personal Team überhaupt nutzbar sind (siehe Kapitel "Nicht umsetzbar…") — falls nicht, muss diese Lösung durch eine eigenständige Widget-Implementierung ohne Datenaustausch ersetzt werden.

## Epic 8 — Persistenz & Migration

Neu aus `ERKENNTNISSE_MACOS.md`, dort als offene Lücke benannt ("von Anfang an einplanen, dieses Projekt hat die Lücke nie geschlossen"):

- **F8.1 Echter SwiftData-Migrationsplan von Anfang an.** `VersionedSchema`/`SchemaMigrationPlan` von der ersten Modellversion an einplanen, statt nur ein flaches `Schema([...])` — die Vorlage musste mangels Migrationsplan einmal die komplette lokale Datenbank löschen, um sie nach mehreren Modelländerungen zu reparieren.
- **F8.2 Technische Falle beim Erweitern von `@Model`-Typen (unbedingt beachten):** Ein neues, nicht-optionales `@Model`-Property braucht seinen Default **direkt an der Property-Deklaration** (z. B. `var isFinal: Bool = false`), nicht nur im `init()` — sonst erkennt SwiftDatas Lightweight-Migration die Änderung nicht und die lokale Datenbank bricht zur Laufzeit mit `no such table`/`no such column` (nur in den App-Logs sichtbar, kein Compiler-Fehler). Gilt unabhängig davon, ob/wann CloudKit (Epic 0, zurückgestellt) später dazukommt — dort wäre es dann eine harte Voraussetzung statt nur einer Best Practice.

## Epic 6 — Einstellungen

- **F6.1** Zugangsdaten-Eingabe (Client-ID/Secret/API-Key).
- **F6.2** Einspeisevergütung einstellbar.
- **F6.3 (offen)** Ggf. Budget-Reserve/Nachladefenster als Einstellung statt Konstante.

## Epic 7 — Tests

- **F7.1** DTO-Decoding-Tests für alle verwendeten Endpunkte.
- **F7.2** Modell-Tests (Autarkiegrad-Berechnung, Vergütungsschätzung).
- **F7.3** Poll-/Backfill-Tests (Lücken-Erkennung, Erstlauf, `isFinal`-Übergang, nachlaufende Nullen).
- **F7.4** OAuth-Client-Tests (Token-Tausch, Refresh, Fehlerfälle).

## Engineering-Konventionen (übernommen aus `ERKENNTNISSE_MACOS.md`)

Keine Features, sondern Arbeitsweisen, die sich in der Vorlage bewährt haben und für dieses Projekt übernommen werden sollen:

- **Durchgängige Dependency Injection:** `URLSession`, `UserDefaults` und eine Uhr (`now: () -> Date`) überall injizierbar statt direkt `.shared`/`.standard`/`Date()` zu verwenden — macht die Fachlogik ohne echte Netzwerk-/Zeitabhängigkeit testbar.
- **Reine Fachlogik-Typen ohne UI-Abhängigkeit** für alles, was testbar sein muss (z. B. Autarkiegrad-Berechnung, Budget-/Drossel-Logik, Backfill-Lückenerkennung) — Views bleiben dünn.
- **Zentrale, injizierbare Drossel-/Budget-Objekte**, ein Objekt pro Limit-Art (siehe Epic 4), statt Rate-Limiting verteilt im Code.
- **Testansatz:** Swift Testing, `URLProtocol`-Stub für Netzwerk, In-Memory-`ModelContainer`, temporäre `UserDefaults`-Instanz, injizierte Uhr — kein Test berührt echte API/Tokens/Datenbank. Die App erkennt einen laufenden Testlauf und startet dann kein Polling und öffnet nicht die echte Datenbank. Zielwert: Testabdeckung der Fachlogik ≥ 80 %.
- **Ein Dokument pro größerem Feature** mit Stand/Entscheidungen vor bzw. während der Umsetzung (wie dieses Backlog) — hat sich bewährt, um Architekturentscheidungen vor der Umsetzung festzuhalten.

## Bewusst zurückgestellt / außerhalb des Scopes

- **Cloud-Synchronisation (Epic 0) und geräteübergreifender Datenzugriff** (inkl. der geplanten macOS-App) — zurückgestellt, da kein bezahlter Apple Developer Account vorhanden ist; siehe Kapitel "Nicht umsetzbar ohne kostenpflichtigen Apple Developer Account". App speichert bis auf Weiteres rein lokal pro Gerät.
- **Export** von Daten (laut Spec-Vorlage explizit auf später verschoben).
- **Mehrfachanlagen-Unterstützung.**
- **Zusammenführung mit einer weiteren Energiedatenquelle** (in der macOS-Vorlage die Wärmepumpe — für dieses iOS-Projekt aktuell nicht vorhanden/relevant, siehe Rückfragen).
- **Schreibender Zugriff** (Batterie-Einstellungen, Storm-Guard, Lasteuerung, EV-Charger Start/Stop) — reines Monitoring-Dashboard, keine `PUT`-Endpunkte.
- **EV-Charger-Auswertung** — nur relevant, falls tatsächlich eine IQ-Wallbox vorhanden ist (zu klären).

## Bekannte Unsicherheiten aus der API-Recherche (nicht app-spezifisch, aber relevant für Zeitplanung/Tests)

- Format der OAuth-Token-Antwort ungetestet.
- Vorzeichen-Konvention von `grid_power`/`battery_power` in `live_data` laut Spec nicht definiert.
- Tatsächliches Monats-/Minutenkontingent des gebuchten Enphase-Plans nicht offiziell bekannt.
- Nachlaufende Nullen in `_lifetime`-Zeitreihen bedeuten "noch nicht gemeldet", nicht "0 Wh".

## Offene Rückfragen an den Nutzer

Alle bisherigen Rückfragen sind geklärt (siehe "Entscheidungen" oben und "Zusammenarbeits-Konventionen" unten).

## Noch zu verifizieren (unabhängig von einer reinen Rückfrage)

- **Tatsächlich verbaute Hardware** — Verbrauchszähler (CT) und/oder IQ-Wallbox (EV-Charger)? Nutzer vermutet "ja", aber unbestätigt (Stand 2026-09-30). Verifizierbar erst mit echtem API-Zugriff über `GET /api/v4/systems/{system_id}/devices` (Abschnitt "Gerätetypen" in `ENPHASE_API_WERTE.md`: Schlüssel `meters` für Verbrauchs-/Produktionszähler, `ev_chargers` für Wallboxen) — sobald F1.1–F1.5 (Auth + Systemerkennung) stehen, diesen Endpunkt einmal gegen die echte Anlage abrufen und hier eintragen. Bis dahin bleiben **F2.1 Verbrauch/Autarkiegrad** und die **EV-Charger-Auswertung** (aktuell unter "Bewusst zurückgestellt") mit dieser Unsicherheit behaftet — falls kein Verbrauchszähler vorhanden ist, liefern `telemetry/consumption_meter`, `energy_import/export_telemetry` etc. laut Doku leere Listen/Nullen statt echter Werte, und Autarkiegrad könnte dann nicht berechnet werden.
