# Shelly API — verfügbare Werte

Übersicht über die **Shelly Cloud API** zur geplanten dritten Datenquelle (siehe `BACKLOG.md`, Abschnitt "Dritte Energiequelle: Shelly-Geräte — Backlog-Idee"). Anders als bei Enphase (inoffizielle OpenAPI-Spec) und Viessmann (echte Rohdaten aus Phase 1) beruht diese Liste auf der **offiziellen Shelly-Dokumentation** (`shelly-api-docs.shelly.cloud`, `kb.shelly.cloud`, `support.shelly.cloud`), abgerufen am 2026-10-14 über Web-Recherche — **nicht** gegen ein echtes Shelly-Konto verifiziert, da noch keine Zugangsdaten/Geräte vorliegen. Shelly dokumentiert laut eigener Aussage bewusst nicht den vollen API-Umfang ("the company prefers to retain the ability to change any of their parameters and result formats") — Abweichungen zum tatsächlichen Verhalten sind wahrscheinlicher als bei den beiden anderen Dokumenten dieses Ordners.

**Dieses Dokument ist reine Recherche, kein Architekturentwurf.** Es beschreibt nur, was die Shelly-API hergibt — welche Teile davon die App tatsächlich nutzt, ist Teil einer späteren Umsetzungsplanung (siehe Backlog-Eintrag).

## Zugriffsvarianten — welche Shelly-Cloud-Schnittstelle passt?

Shelly bietet laut eigener Dokumentation **drei** getrennte Cloud-Schnittstellen für unterschiedliche Zielgruppen — wichtig, die richtige zu wählen, bevor irgendetwas umgesetzt wird:

| Schnittstelle | Zweck | Authentifizierung | Zielgruppe |
|---|---|---|---|
| **Cloud Control API** | Eigene Geräte im eigenen Shelly-Konto steuern/auslesen | HTTP: `auth_key` aus den App-Einstellungen · WebSocket (Echtzeit): OAuth mit langlebigem Access-Token | Einzelpersonen/Heimautomation, kleine Projekte, Prototypen |
| **Integrator API** | Cloud-zu-Cloud-Integration für viele **fremde** Endkundenkonten | Consent-Flow pro Endnutzer, Integrator erhält ein JWT pro Kundenkonto | B2B/Plattformen mit vielen unabhängigen Kunden (z. B. Smart-Home-Ökosysteme) — **nicht self-service**, erfordert kommerzielle Freigabe durch Shelly nach Prüfung |
| **Shelly Fleet Manager (SFM)** | Unabhängige Geräteverwaltung ganz ohne Shelly-Cloud-Konto | Geräte verbinden sich direkt per WebSocket zum Fleet Manager | Installateure/Facility-Management mit vielen Geräten an mehreren Standorten, nur Gen2+ |

**Für diese App relevant: die Cloud Control API.** Sie passt zum bestehenden Muster — ein einzelner Nutzer greift mit seinen **eigenen** Zugangsdaten auf seine **eigenen** Geräte zu (wie bereits bei Enphase/Viessmann, wo der Nutzer seine eigene Developer-App im jeweiligen Portal anlegt). Die Integrator API wäre erst relevant, wenn die App an viele fremde Shelly-Konten verteilt werden sollte — das ist laut Backlog-Eintrag nicht der Plan.

**Wichtiger Unterschied zu Enphase/Viessmann:** Für die reinen HTTP-Endpunkte (Status abrufen, schalten) braucht es **keinen OAuth-Flow** — nur einen einmalig in der Shelly-App generierten `auth_key`, vom Nutzer selbst kopiert, analog zu Enphases API-Key, aber ohne Authorization-Code-Austausch. Ein echter OAuth2-Flow existiert bei Shelly nur für den optionalen WebSocket-Echtzeit-Kanal (siehe unten) — laut Doku selbst "work in progress".

## Zugriff, Authentifizierung & Limits (Cloud Control API)

| Aspekt | Wert |
|---|---|
| Server-URI | **Mandantenbasiert, pro Konto unterschiedlich** (z. B. `shelly-XX-eu.shelly.cloud`) — wird zusammen mit dem `auth_key` in der Shelly-App angezeigt. Laut Doku ausdrücklich *"subject to change and is not guaranteed"* (Server-Umzüge aus Kapazitätsgründen möglich) — die App darf die URI nicht fest verdrahten, sondern muss sie pro Nutzer aus der App-Konfiguration übernehmen |
| Authentifizierung (HTTP) | `auth_key`-Parameter (Query oder Body) — generiert in der Shelly-App unter "User settings → Authorization cloud key". **Ändert sich automatisch bei einer Passwortänderung des Shelly-Kontos** (muss dann neu eingegeben werden) |
| Rate-Limit | **1 Anfrage pro Sekunde**, für beide API-Versionen (v1 und v2.0-beta) ausdrücklich dokumentiert — deutlich strenger als Enphases Minutenlimit, aber ohne bekanntes Monatskontingent |
| API-Versionen | **v2.0-beta** (aktuell, JSON-Body, empfohlen) und die ältere, als *deprecated* markierte **v1** (form-encoded Parameter) — v1 bleibt vorerst nutzbar, sollte aber für einen Neuaufbau nicht mehr Grundlage sein |
| Voraussetzung | Aktives Shelly-Cloud-Konto, Geräte dort registriert (App-Einrichtung, nicht Teil der API) |

## Geräte-Discovery

Anders als bei Enphase (`GET /systems`) oder Viessmann (`installations?includeGateways=true`) ist die Geräteliste bei Shelly **kein Teil der dokumentierten v2-Schnittstelle**, sondern ein separater, nur in der Community dokumentierter Endpunkt:

| Endpunkt | Methode | Zweck |
|---|---|---|
| `/interface/device/list` | POST (`auth_key`) | Liste aller Geräte-IDs, auf die das Konto Zugriff hat — nötig, um die für `v2/devices/api/get` benötigten IDs überhaupt erst zu bekommen |
| `/device/all_status?show_info=true&no_shared=true` | GET (`auth_key`) | Statuswerte **aller** Geräte des Kontos in einem Aufruf (`data.devices_status`, ein Feld pro Geräte-ID) — vermeidet, bei vielen Geräten einzeln über `v2/devices/api/get` (max. 10 IDs/Aufruf) nachfragen zu müssen |

## Status abrufen (v2.0-beta, empfohlen)

| Endpunkt | Methode | Beschreibung |
|---|---|---|
| `/v2/devices/api/get?auth_key=<KEY>` | POST | Body: `ids` (1–10 Geräte-IDs, Pflicht) · optional `select: ["status","settings"]` · optional `pick.status`/`pick.settings` (Feldfilter). Antwort: Array je Gerät mit `id`, `type`, `code`, `gen` (1/2), `online`, `status`, `settings` |

## Geräte steuern (v2.0-beta)

**Schreibender Zugriff — relevant für den im Backlog-Eintrag diskutierten "ersten schreibenden Endpunkt" der App, siehe dortige Sicherheitsüberlegungen (Bestätigungsdialog etc.).**

| Endpunkt | Methode | Body | Für |
|---|---|---|---|
| `/v2/devices/api/set/switch?auth_key=<KEY>` | POST | `id` (Pflicht) · `channel` (Default 0) · `on: true/false` (Pflicht) · `toggle_after` (s, optional, automatisches Zurückschalten) | Relais/Steckdosen |
| `/v2/devices/api/set/cover?auth_key=<KEY>` | POST | `id` · `channel` · `position: "open"/"close"/"stop"` oder `0–100` · `duration` (s) · `relative: -100…100` (nicht kombinierbar mit `position`) · `slatPosition`/`slatRelative` (Lamellen) | Rollläden |
| `/v2/devices/api/set/light?auth_key=<KEY>` | POST | `id` · `channel` · `on` · `toggle_after` · `mode: "color"/"white"` · `temperature` (2700–7000K) · `brightness` (0–100 %) · `red`/`green`/`blue`/`white` (0–255) · `gain` (0–100) · `effect` (0–6) | Lampen |
| `/v2/devices/api/set/groups?auth_key=<KEY>` | POST | Objekte `switch`/`cover`/`light`, je mit `ids[]` + den gleichen Feldern wie oben | Mehrere Geräte gleichzeitig |

**Fehlercodes:** HTTP 400 (`DEVICE_FAILED_COMMAND`, `DEVICE_OFFLINE`, `DEVICE_INVALID_MODE`, `DEVICE_INVALID_CHANNEL`, `BAD_REQUEST`), 404 (`DEVICE_NOT_FOUND`, `INSTANCE_NOT_FOUND`), 500 (`UNEXPECTED_SUBSERVICE_ERROR`). Erfolgreiche Einzelgeräte-Befehle antworten mit HTTP 200.

## Legacy-API v1 (deprecated, aber noch aktiv)

Form-encoded statt JSON, ein Request pro Gerät/Kanal (kein Batch wie bei v2). Nur der Vollständigkeit halber dokumentiert — **für eine Neuimplementierung nicht empfohlen**, Shelly empfiehlt selbst die Migration auf v2.0-beta.

| Endpunkt | Parameter |
|---|---|
| `POST /device/status` | `id`, `auth_key` |
| `POST /device/relay/control` | `id`, `auth_key`, `channel`, `turn: "on"/"off"` |
| `POST /device/relay/roller/control` | `id`, `auth_key`, `direction: "open"/"close"/"stop"` oder `pos: 0–100` |
| `POST /device/light/control` | `id`, `auth_key`, `turn`, Farbmodus: `red`/`green`/`blue`/`white` (0–255), `gain` (0–100) · Weißmodus: `channel`, `brightness` (0–100) |
| `POST /device/relay/bulk_control` / `/device/light/bulk_control` / `/device/roller/bulk_control` | Analoge Mehrfachsteuerung |
| `POST /scene/list` / `/scene/get` / `/scene/delete` / `/scene/manual_run` | Shelly-Cloud-"Szenen" (in der App definierte Aktionsfolgen) verwalten/auslösen |

## Geräte-/Firmware-Generationen — unterschiedliche Status-Felder

Die von `/v2/devices/api/get` bzw. `/device/all_status` gelieferten `status`-Objekte spiegeln direkt das **lokale** Datenmodell des jeweiligen Geräts — und das unterscheidet sich stark zwischen Gen1 (älter, Mongoose-OS) und Gen2+ (aktuell, JSON-RPC-Komponentenmodell). Welches Format relevant ist, hängt von den beim Nutzer tatsächlich verbauten Geräten ab (noch offen, siehe Backlog-Eintrag).

### Gen1 (ältere Geräte, z. B. Shelly1/1PM, Shelly Plug-S, Shelly EM, Shelly 3EM)

| Struktur | Felder |
|---|---|
| `relays[]` (schaltbare Geräte) | `ison` (bool) · `overpower` · `has_timer`/`timer_started`/`timer_duration`/`timer_remaining` · `source` |
| `meters[]` (1-Kanal-Leistungsmessung, z. B. Plug-S) | `power` (W) · `overpower` (W) · `is_valid` (bool) · `timestamp` · `counters[]` (letzte 3 Minuten) · `total` (Wh, kumulativ seit Neustart) |
| `emeters[]` (3-Phasen-Geräte, z. B. 3EM) | pro Phase: `power` (W) · `pf` (Leistungsfaktor) · `current` (A) · `voltage` (V) · `is_valid` · `total`/`total_returned` (Wh) · zusätzlich Top-Level `total_power` (Summe aller Phasen) |

### Gen2+ (aktuelle Geräte, JSON-RPC-Komponentenmodell, z. B. Shelly Plus/Pro-Serie)

| Komponente | Geräte | Felder (`<Komponente>.GetStatus`) |
|---|---|---|
| `Switch` | Schaltbare Relais/Steckdosen mit Leistungsmessung (z. B. Plus Plug S) | `id` · `output` (bool) · `source` · `apower` (W) · `voltage` (V) · `current` (A) · `freq` (Hz) · `aenergy.total` (Wh, kumulativ) · `aenergy.by_minute[]` (mWh, letzte 3 Minuten) · `aenergy.minute_ts` · `ret_aenergy.*` (zurückgespeiste Energie, analog) · `temperature.tC`/`.tF` |
| `PM1` | Reine Leistungsmesser ohne Relais (z. B. PM Mini) | Gleiche Felder wie `Switch`, aber ohne `output`/Schaltfunktion |
| `EM1` | 1-Kanal-Energiezähler (z. B. Pro EM, pro Kanal eine `EM1`-Instanz) | `id` · `current` (A) · `voltage` (V) · `act_power` (W, Wirkleistung) · `aprt_power` (VA, Scheinleistung) · `pf` (Leistungsfaktor) · `freq` (Hz) · `calibration` |
| `EM` | 3-Phasen-Energiezähler (z. B. Pro 3EM) | Pro Phase (`a_`/`b_`/`c_`-Präfix): `current`, `voltage`, `act_power`, `aprt_power`, `pf`, `freq` · zusätzlich `total_current`, `total_act_power`, `total_aprt_power` |
| `EM1Data`/`EMData` | Kumulative Energie zu `EM1`/`EM`, **separater Aufruf** (`.GetData`, nicht Teil von `GetStatus`) | `total_act_energy` (Wh) · `total_act_ret_energy` (Wh, zurückgespeist) · `lag_react_energy`/`lead_react_energy` (Blindenergie) · `max_act_power`/`min_act_power` · `max_aprt_power`/`min_aprt_power` |

**Wichtige Falle, aus Community-Berichten (noch nicht selbst verifiziert):** `EM`/`EM1` liefern **keine** kumulative Energie in `GetStatus` (anders als `Switch`/`PM1` mit `aenergy`) — für Tages-/Lebenszeit-Summen ist zwingend der separate `EM1Data.GetData`/`EMData.GetData`-Aufruf nötig. Bei einer Umsetzung mit einem Energiezähler-Gerät (EM/EM1/Pro-Serie) unbedingt beide Aufrufe einplanen, nicht nur `GetStatus`.

**Tagesenergie aus `aenergy.total` (F12.3, 2026-10-14 umgesetzt, noch am selben Tag wieder entfernt — siehe BACKLOG.md):** `aenergy.total` ist seit dem letzten Geräteneustart kumulativ, keine Tagesgröße — ein "heute verbraucht"-Wert lässt sich daraus nur als Differenz zweier Zählerstände schätzen, nicht aus einem einzelnen Abruf ablesen. Genau das machte die Anzeige nach dem Hinzufügen neuer Steckdosen unbrauchbar (immer `0 Wh` beim ersten Messwert) und führte zur Entfernung. Bei einer künftigen Neuumsetzung: einen Geräteneustart (Zählerstand springt auf 0 zurück) erkennen und nie als negativen Verbrauch werten; ohne Hintergrund-Poll (F16.1 noch offen) kann zwischen zwei Abrufen Mitternacht liegen, was eine Schätzung statt eines exakten Werts erzwingt.

**Erstmals gegen ein echtes Konto verifiziert (2026-10-14, Shelly Plug M Gen3, Bugreport "Daten nicht im korrekten Format"):** Die Top-Level-Hülle von `/v2/devices/api/get` ist tatsächlich das dokumentierte bare Array — der eigentliche Fehler lag auf Feldebene, wo zwei Annahmen aus der offiziellen Doku nicht zutrafen:
- `gen` ist ein **String** (`"G2"`), keine Zahl `1`/`2` wie angenommen. Ein Gen3-Gerät meldet hier `"G2"`, da es intern dasselbe JSON-RPC-Komponentenmodell wie Gen2 nutzt — `gen` spiegelt die Protokollfamilie, nicht die Marketing-Generation.
- `online` ist `0`/`1` (Zahl), kein JSON-Bool `true`/`false`.
- `type` liefert die Geräte-Kategorie (z. B. `"relay"`), keinen Modellnamen — der Modellname steckt in `code` (z. B. `"S3PL-30110EU"`).

`ShellyDeviceStatusDTO` (`ShellyDTO.swift`) decodiert `gen`/`online` seither tolerant gegen beide Varianten (String/Zahl bzw. Bool/Zahl).

## Echtzeit-Events (WebSocket, optional)

Für Push-Updates statt Polling bietet Shelly einen WebSocket-Kanal — **mit echtem OAuth2-Flow**, anders als die auth_key-basierten HTTP-Endpunkte oben:

1. **Autorisierung:** `GET https://my.shelly.cloud/oauth_login.html?client_id=<CLIENT_ID>&redirect_uri=<CALLBACK>&state=<CSRF>` — für eigene/experimentelle Nutzung reicht laut Doku `client_id=shelly-diy` (keine Shelly-Freigabe nötig, im Gegensatz zur Integrator API oben).
2. **Code-Tausch:** `GET/POST https://<shelly_server>/oauth/auth?client_id=<CLIENT_ID>&grant_type=code&code=<CODE>` → liefert ein **JWT-Access-Token**. Das Token enthält ein `user_api_url`-Feld, das den für diesen Nutzer zuständigen Server für alle weiteren Aufrufe benennt (passend zur mandantenbasierten Server-Zuordnung oben).
3. **Verbindung:** `wss://<shelly_cloud_server>:6113/shelly/wss/hk_sock?t=<ACCESS_TOKEN>`
4. **Event-Typen:** `Shelly:StatusOnChange` (Status eines Geräts geändert) · `Shelly:Online` (Online-Status geändert, Feld `online`) · `Shelly:CommandResponse` (Antwort auf einen per `Shelly:CommandRequest` gesendeten Befehl, verknüpft über `trid`)

**Architektur-Einordnung (noch keine Entscheidung, nur Beobachtung):** Ein dauerhafter WebSocket passt nicht zum bisherigen Poll-Muster der App (Enphase/Viessmann pollen periodisch, auch das Widget pollt nur auf Zeitplan statt eine offene Verbindung zu halten) und wäre unter iOS-Hintergrund-Restriktionen ohnehin nicht dauerhaft offen zu halten — für eine erste Umsetzung ist reines HTTP-Polling über die Cloud Control API (`auth_key`) der naheliegendere, zum bestehenden Architekturmuster passende Weg. Echtzeit-Events wären höchstens relevant, solange die App im Vordergrund ist.

## Sicherheit

- `auth_key` ist funktional gleichwertig zu einem Passwort für die Geräte des Kontos — "Do not share your Authorization key with anyone" (Shelly-eigene Warnung). Gehört wie Enphase-/Viessmann-Secrets in die Keychain, nie ins Log.
- `auth_key` **ändert sich automatisch bei einer Shelly-Account-Passwortänderung** — die App muss diesen Fall erkennen (Anfragen schlagen dann mit einem Auth-Fehler fehl) und zur erneuten Eingabe auffordern, es gibt keinen Refresh-Token-Mechanismus wie bei Enphase/Viessmann.
- Server-URI ist nicht stabil garantiert (siehe oben) — nicht hartkodieren, sondern als Teil der vom Nutzer hinterlegten Zugangsdaten behandeln.

## Noch offen / zu verifizieren

- **Welche konkreten Shelly-Geräte der Nutzer tatsächlich besitzt** (Gen1 vs. Gen2+, Switch/PM1 vs. EM/EM1/EM3) — bestimmt, welche Status-Felder/Komponenten überhaupt relevant sind. Siehe Backlog-Eintrag.
- **Tatsächliches Rate-Limit-Verhalten bei Überschreitung** (HTTP-Statuscode/Antwortformat bei >1 Anfrage/Sekunde) — in der Doku nicht beschrieben, nur die Grenze selbst.
- **Tatsächliches Format von `/device/all_status`/`/interface/device/list`** — beide Endpunkte stammen aus Community-Quellen (Shelly-Forum, Drittanbieter-Wikis), nicht aus der offiziellen API-Referenz selbst; vor Verwendung gegen ein echtes Konto verifizieren.
- **Ob ein kostenloses Shelly-Cloud-Konto für die Nutzung von `auth_key` genügt**, oder ob (wie bei manchen Cloud-Zusatzfunktionen anderer Hersteller) ein Abo nötig ist — in der gesichteten Doku nicht erwähnt, vermutlich nicht nötig, aber unbestätigt.
- **Token-Lebensdauer des OAuth-Access-Tokens** für den WebSocket-Kanal ("langlebig" laut Doku, keine konkrete Zeitangabe gefunden) — nur relevant, falls Echtzeit-Events später doch umgesetzt werden.
- **Tatsächliches Antwortformat bei einem abgelehnten `auth_key`** (F11.4) — nicht offiziell dokumentiert, ob dies konsistent als HTTP 401/403 zurückkommt oder (wie bei manchen älteren Shelly-Cloud-Endpunkten berichtet) auch mit HTTP 200 und `{"isok": false, "errors": {...}}`. Die App erkennt deshalb beide Formen tolerant (`ShellyClient.isAuthFailure`) — vor einem echten Kontotest noch unverifiziert.
