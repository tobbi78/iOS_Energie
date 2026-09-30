# Enphase API — verfügbare Werte

Übersicht über alle Endpunkte und Felder der **Enphase Monitoring API v4** (Enlighten Systems API). Anders als `VIESSMANN_API_WERTE.md` beruht diese Liste **nicht** auf eigenen gesammelten Rohdaten, sondern auf der Spezifikation: Quelle ist die inoffizielle OpenAPI-3-Fassung [andrewdmontgomery/Enphase-OpenAPI](https://github.com/andrewdmontgomery/Enphase-OpenAPI) (Commit `7af87c2`, 2025-10-19), die per Skript 1:1 aus Enphases eigenem Swagger (`https://developer-v4.enphase.com/swagger/spec/System_API.json`) konvertiert wird. Die offizielle Seite <https://developer-v4.enphase.com/docs/monitoring_api> war aus der Arbeitsumgebung nicht erreichbar (Netzwerk-Policy), Abweichungen zum aktuellen Stand dort sind möglich.

**Wie zu lesen:** Jede Zeile einer Tabelle ist ein *Endpunkt* (Pfad relativ zur Basis-URL, `{system_id}` = numerische Anlagen-ID). Die Spalte "Felder" listet die Felder der JSON-Antwort mit Einheit und einem Beispielwert **aus der Spezifikation** (keine echten Werte unserer Anlage). Verschachtelte Felder sind mit `.` notiert, Listen mit `[]`. Das in vielen Antworten wiederkehrende `meta`-Objekt ist unten einmal separat beschrieben.

Welche Endpunkte bei **unserer** Anlage tatsächlich Daten liefern, hängt von der Hardware ab (Produktionszähler/Verbrauchszähler/Batterie vorhanden?) — Endpunkte für nicht vorhandene Geräte liefern leere Listen bzw. Nullen. Sobald echte Rohdaten vorliegen, sollte diese Liste analog zur Viessmann-Datei gegen beobachtete Werte abgeglichen werden.

## Zugriff, Authentifizierung & Limits

| Aspekt | Wert |
|---|---|
| Basis-URL | `https://api.enphaseenergy.com` (bestätigt durch die OAuth-URLs der eigenen Developer-App; die Spec enthält nur den QA-Server `https://api-qa2.enphaseenergy.com`) |
| Authentifizierung | **Zwei Header pro Request:** `Authorization: Bearer <OAuth-2.0-Access-Token>` **und** `key: <API-Key der Developer-App>` |
| Token | OAuth 2.0, Authorization-Code-Flow — Ablauf siehe nächster Abschnitt |
| Rate-Limit | Plan-abhängig, pro **Minute und pro Monat**. Überschreitung → HTTP `429` mit `period` ("minute"/"month"), `period_start`, `period_end`, `limit` (Spec-Beispiel: Plan "Kilowatt", `limit`: 5 pro Minute). Konkrete Kontingente der Pläne (Watt/Kilowatt/…) stehen nicht in der Spec |
| Zeitformat | Zeitpunkte als **Unix-Epoch in Sekunden** (`*_at`), Tage als `YYYY-MM-DD` (`*_date`); Ausnahme EV-Charger: `YYYYMMDD` |
| Energie/Leistung | Energie immer in **Wh**, Leistung in **W** (Integer) |
| Fehlercodes | `401` (Token), `403` (kein Zugriff/Plan), `404`, `405`, `422` (ungültige Parameter, z. B. Zeitraum zu lang), `429` (Limit), `501`; `live_data` zusätzlich `461`–`473`, `550`–`552` |

## OAuth-Ablauf (Token beschaffen)

Quelle: Autorisierungs-URL der eigenen Developer-App und Beispiel-Request aus dem Enphase-Portal (nicht Teil der OpenAPI-Spec).

**1. Freigabe durch den Anlagenbesitzer (Browser)**

```
GET https://api.enphaseenergy.com/oauth/authorize?response_type=code&client_id=<CLIENT_ID>&redirect_uri=https://api.enphaseenergy.com/oauth/redirect_uri
```

Der Besitzer meldet sich bei Enlighten an und bestätigt den Zugriff. Danach leitet Enphase auf die `redirect_uri` weiter und hängt `?code=<CODE>` an (Beispiel: `2TJk7M`, also ein kurzer Code). Der Code gilt nur für **einen** Token-Tausch.

**2. Code gegen Token tauschen**

```
POST /oauth/token?grant_type=authorization_code&redirect_uri=https://api.enphaseenergy.com/oauth/redirect_uri&code=<CODE> HTTP/1.1
Host: api.enphaseenergy.com
Authorization: Basic <base64(CLIENT_ID:CLIENT_SECRET)>
```

| Aspekt | Wert |
|---|---|
| Parameter | Alle drei Werte (`grant_type`, `redirect_uri`, `code`) stehen als **Query-Parameter** in der URL, der Request hat keinen Body |
| Client-Authentifizierung | HTTP Basic: `base64("<client_id>:<client_secret>")` |
| `redirect_uri` | Muss **identisch** mit der Angabe in Schritt 1 und mit der in der Developer-App hinterlegten URI sein. Standard ist Enphases eigene Seite `https://api.enphaseenergy.com/oauth/redirect_uri`, auf der der Code zum Kopieren angezeigt wird. Eine App-eigene URI (z. B. ein Custom-URL-Scheme) muss vorher im Portal eingetragen werden |
| Zugangsdaten | `client_id`, `client_secret` und API-Key (`key`-Header) stammen aus der Developer-App im Enphase-Portal |

**Noch offen, weil von uns noch nicht beobachtet:** das Format der Token-Antwort (erwartet werden `access_token`, `refresh_token`, `expires_in`), die Laufzeiten der Tokens und der Refresh-Request (erwartet: derselbe Endpunkt mit `grant_type=refresh_token&refresh_token=<…>`). Das bitte beim ersten echten Tausch nachtragen.

**Sicherheit:** Client-Secret, API-Key, Codes und Tokens gehören nicht ins Repo und nicht in Logs. Ein Base64-kodierter Basic-Header ist **nicht verschlüsselt**, sondern nur umkodiert: Wer ihn sieht, kann daraus Client-ID und Secret direkt zurücklesen.

## Gemeinsames `meta`-Objekt

In fast allen Zeitreihen-/Telemetrie-Antworten enthalten.

| Feld | Bedeutung | Beispiel |
|---|---|---|
| `meta.status` | Anlagenstatus (Werte siehe Abschnitt "Statuswerte") | "normal" |
| `meta.last_report_at` | Letzter Report des Gateways (Envoy) | 1445619615 |
| `meta.last_energy_at` | Letzte gemeldete Produktion (auch wenn 0) | 1445619033 |
| `meta.operational_at` | Inbetriebnahme (Netzanschluss-Zeitpunkt) | 1357023600 |

## Anlage (System Details)

| Endpunkt | Bezeichnung | Felder |
|---|---|---|
| `GET /api/v4/systems` | Liste aller Anlagen, auf die der Token Zugriff hat (Paging `page`, `size` ≤100, `sort_by` `id`/`-id`) | `total`, `current_page`, `size`, `count` · `systems[]`: `system_id`: 698910067 · `name`: "Enphase System" · `public_name`: "Residential System" · `timezone`: "Australia/Sydney" · `address.city`/`.state`/`.country`/`.postal_code` · `connection_type`: "ethernet"/"Wi-Fi"/"Cellular" · `status`: "micro" · `last_report_at` · `last_energy_at` · `operational_at` · `attachment_type`: "acm" · `interconnect_date` · `reference`/`other_references` · `energy_lifetime`/`energy_today`/`system_size`: **veraltet, immer -1** |
| `POST /api/v4/systems/search` | Anlagen suchen/filtern (Body `system`: `ids`, `name`, `reference`, `statuses[]` …; `size` ≤1000) | wie oben |
| `GET /api/v4/systems/{system_id}` | Einzelne Anlage | wie ein Eintrag aus `systems[]` |
| `GET /api/v4/systems/{system_id}/summary` | **Anlagen-Zusammenfassung (Momentwerte)** | `current_power` (W): 0 · `energy_today` (Wh): 0 · `energy_lifetime` (Wh): 0 · `size_w` (W, Anlagengröße): 1250 · `modules`: 5 · `source`: "meter" · `status`: "normal" · `summary_date`: "2019-05-12" · `last_interval_end_at` · `last_report_at` · `operational_at` · `nmi` (National Meter Identifier) · `battery_charge_w`/`battery_discharge_w` (W, max.): 1280 · `battery_capacity_wh` (Wh): 3360 |
| `GET /api/v4/systems/{system_id}/devices` | Aktive Geräte der Anlage, gruppiert nach Typ | `total_devices`: 11 · `devices.<typ>[]` (siehe "Gerätetypen") |
| `GET /api/v4/systems/retrieve_system_id?serial_num=…` | System-ID zu Envoy-Seriennummer | `system_id` |
| `GET /api/v4/systems/inverters_summary_by_envoy_or_site` | Wechselrichter-Übersicht je Envoy/Anlage (`site_id` oder `envoy_serial_number`, Paging) | `[].signal_strength` · `[].micro_inverters[]`: `id`, `serial_number`, `model`, `part_number`, `sku`, `status`, `power_produced.value`/`.units` (aktuelle Leistung), `energy.value`/`.units` (Lebensdauer-Energie), `proc_load`, `param_table`, `grid_profile`, `envoy_serial_number`, `last_report_date` |

### Gerätetypen in `devices`

Alle Einträge haben `id`, `name`, `serial_number`, `part_number`, `sku`, `model`, `status`: "normal", `active`: true, `last_report_at`, `product_name`.

| Schlüssel | Gerät | Zusatzfelder / Beispiel |
|---|---|---|
| `micros` | Mikrowechselrichter | `sku`: "IQ8A-72-2-US" · `model`: "M250" |
| `meters` | Zähler (Produktion/Verbrauch) | `name`: "production"/"consumption" · `state`: "enabled" · `config_type`: "Net"/"Production" · `product_name`: "RGM" |
| `gateways` | IQ Gateway / Envoy | `emu_sw_version`: "D4.6.11.170403 (799d2d)" · `cellular_modem.imei`/`.plan_start_date`/`.plan_end_date` |
| `q_relays` | IQ Relay | `sku`: "Q-RELAY-1P-INT" |
| `acbs` | AC Battery (alt) | `product_name`: "ACB" |
| `encharges` | IQ Battery | `product_name`: "IQ Battery R3 - 5P" |
| `enpowers` | IQ System Controller | `product_name`: "IQ System Controller" |
| `ev_chargers` | IQ EV Charger | `model`: "IQ-EVSE-60R" · `firmware`: "v0.04.17" |

## Momentanwerte (Echtzeit)

Für ein Dashboard die relevantesten Endpunkte.

| Endpunkt | Bezeichnung | Felder |
|---|---|---|
| `GET /api/v4/systems/{system_id}/latest_telemetry` | **Zuletzt gemeldete Leistung je Zähler/Batterie** (Stand des letzten Gateway-Reports) | `devices.meters[]`: `name`: "production"/"consumption" · `channel`: 1–3 (Phase) · `power` (W): 755 · `last_report_at` · `devices.encharges[]`: `power` (W, Vorzeichen-Konvention in der Spec nicht definiert): -15 · `operational_mode`: "Idle" · Kanäle ohne Report >7 Tage: `power`/`last_report_at` = null |
| `GET /api/v4/systems/{system_id}/live_data` | **Live-Stream** (Header `duration` 30–300 s, Default 30) | `data.data.pv_power` (W): 30 · `consumption_power` (W): 15 · `grid_power` (W, negativ = Einspeisung): -10 · `battery_power` (W): 5 · `battery_soc` (%): 40 · `generator_power` (W): 0 · `grid_status`: "On Grid" · `battery_mode`: "Savings Mode" · `envoy_serial_number[]` · `timestamp_epoch` (**ms**): 1679041508556 · `timestamp_utc` |
| `GET /api/v4/systems/config/{system_id}/grid_status` | Netzstatus | `grid_state`: "On Grid"/"Off Grid"/"Unknown" · `last_report_date` |

**Hinweis `live_data`:** Setzt laut Spec-Fehlercodes eine direkt erreichbare, aktuelle Gateway-Firmware voraus (eigene Fehler `461`–`473`/`55x` für Gateway-/Verbindungsprobleme). Vorzeichen von `grid_power`/`battery_power` sind in der Spec nicht ausdrücklich definiert — vor Nutzung mit echten Werten verifizieren.

## Produktion (PV)

| Endpunkt | Bezeichnung | Felder |
|---|---|---|
| `GET /api/v4/systems/{system_id}/telemetry/production_micro` | Produktion aller Mikrowechselrichter, **5-min-Intervalle** (`start_at`/`start_date`, `granularity` `5mins`/`15mins`/`day`/`week`) | `total_devices` · `intervals[]`: `end_at` · `devices_reporting` · `powr` (W, Mittel): 30 · `enwh` (Wh): 40 |
| `GET /api/v4/systems/{system_id}/telemetry/production_meter` | Produktion laut Produktionszähler, **15-min-Intervalle** | `intervals[]`: `end_at` · `devices_reporting` · `wh_del` (Wh) |
| `GET /api/v4/systems/{system_id}/rgm_stats` | Revenue-Grade-Meter-Statistik, 15-min, max. 7 Tage je Abruf | `intervals[]`: `end_at` · `devices_reporting` · `wh_del` (Wh) · `meter_intervals[]`: `meter_serial_number`, `envoy_serial_number`, `intervals[]`: `channel`, `end_at`, `wh_del` (Wh), `curr_w` (W) |
| `GET /api/v4/systems/{system_id}/production_meter_readings` | Zählerstand je Produktionszähler zum Zeitpunkt `end_at` | `meter_readings[]`: `serial_num` · `value` (Wh, kumulativ) · `read_at` |
| `GET /api/v4/systems/{system_id}/energy_lifetime` | **Tages-Zeitreihe** Produktion (`start_date`/`end_date`, Default bis gestern) | `start_date`: "2013-01-01" · `production[]` (Wh/Tag): [15422, 15421, …] · mit `production=all` zusätzlich `micro_production[]`, `meter_production[]` · `meter_start_date` (ab wann Zählerwerte statt Wechselrichterwerte) |

## Verbrauch & Netz (Bezug/Einspeisung)

Nur mit installiertem **Verbrauchszähler** (CT) befüllt.

| Endpunkt | Bezeichnung | Felder |
|---|---|---|
| `GET /api/v4/systems/{system_id}/telemetry/consumption_meter` | Hausverbrauch, **15-min-Intervalle** | `total_devices` · `intervals[]`: `end_at` · `devices_reporting` · `enwh` (Wh): 40 |
| `GET /api/v4/systems/{system_id}/energy_import_telemetry` | **Netzbezug**, 15-min | `intervals[][]` (**Liste von Listen**): `end_at` · `wh_imported` (Wh): 40 · `total_devices` immer 0 |
| `GET /api/v4/systems/{system_id}/energy_export_telemetry` | **Einspeisung**, 15-min | `intervals[][]`: `end_at` · `wh_exported` (Wh) |
| `GET /api/v4/systems/{system_id}/consumption_lifetime` | Tages-Zeitreihe Verbrauch | `start_date` · `consumption[]` (Wh/Tag) |
| `GET /api/v4/systems/{system_id}/energy_import_lifetime` | Tages-Zeitreihe Netzbezug | `start_date` · `import[]` (Wh/Tag) |
| `GET /api/v4/systems/{system_id}/energy_export_lifetime` | Tages-Zeitreihe Einspeisung | `start_date` · `export[]` (Wh/Tag) |

**Hinweis Tages-Zeitreihen (`*_lifetime`):** Ein Wert pro Tag ohne Lücken; **nachlaufende Nullen** bedeuten "noch nicht gemeldet", nicht "0 Wh" — beim Auswerten nicht als echte Null interpretieren.

## Batterie

| Endpunkt | Bezeichnung | Felder |
|---|---|---|
| `GET /api/v4/systems/{system_id}/telemetry/battery` | Alle Batterien, 15-min | `intervals[]`: `end_at` · `charge.enwh` (Wh): 40 · `discharge.enwh` (Wh) · `soc.percent` (%): 25 · jeweils `.devices_reporting` · `last_reported_aggregate_soc`: "97%" (**String** mit %) |
| `GET /api/v4/systems/{system_id}/devices/encharges/{serial_no}/telemetry` | Einzelne IQ Battery | `intervals[]`: `end_at`, `charge.enwh`, `discharge.enwh`, `soc.percent` · `last_reported_time` · `last_reported_soc` |
| `GET /api/v4/systems/{system_id}/devices/acbs/{serial_no}/telemetry` | Einzelne AC Battery | wie Encharge |
| `GET /api/v4/systems/{system_id}/battery_lifetime` | Tages-Zeitreihe | `charge[]` / `discharge[]` (Wh/Tag) |

## Einzelgeräte (Wechselrichter)

| Endpunkt | Bezeichnung | Felder |
|---|---|---|
| `GET /api/v4/systems/{system_id}/devices/micros/{serial_no}/telemetry` | Einzelner Mikrowechselrichter, 5-min | `serial_number` · `intervals[]`: `end_at` · `powr` (W) · `enwh` (Wh) |

## Konfiguration (lesen & schreiben)

`PUT` ändert die Anlage — für ein reines Monitoring-Dashboard nicht vorgesehen.

| Endpunkt | Bezeichnung | Felder |
|---|---|---|
| `GET`/`PUT /api/v4/systems/config/{system_id}/battery_settings` | Batterie-Einstellungen | `battery_mode`: "Self-consumption"/"Savings Mode"/"Full Backup" · `reserve_soc` (%): 95 · `energy_independence`: "enabled" · `charge_from_grid`: "disabled" · `battery_shutdown_level` (%): 13 |
| `GET`/`PUT /api/v4/systems/config/{system_id}/storm_guard` | Unwetter-Schutz | `storm_guard_status` · `storm_alert` |
| `GET`/`PUT /api/v4/systems/config/{system_id}/load_control` | Laststeuerung (Trockenkontakte) | `load_control_data[]`: `name`, `load_name`, `owner_can_override`, `mode`, `soc_low`/`soc_high` (%), `status`, `essential_start_time`/`essential_end_time` (s) |

## Ereignisse & Alarme

`start_time` Pflicht, max. 9 Monate zurück, max. 1 Woche pro Abruf.

| Endpunkt | Bezeichnung | Felder |
|---|---|---|
| `GET /api/v4/systems/{system_id}/events` | Ereignisse | `events[]`: `status`: "Info"/"Open"/"Closed" · `event_type_id` · `event_start_time`/`event_end_time` · `serial_number` |
| `GET /api/v4/systems/{system_id}/alarms` | Alarme (`cleared=true` für geschlossene) | `alarms[]`: `id` · `event_type_id` · `cleared` · `alarm_start_time`/`alarm_end_time` · `severity`: 1=FATAL … 6=NONE · `events[]`: `serial_number`, `start_date`, `end_date` |
| `GET /api/v4/systems/event_types` | Katalog der Ereignistypen | `event_types[]`: `event_type_id` · `event_type_key` · `stateful` · `event_name` · `event_description` · `recommended_action` |

## EV-Charger

Nur relevant, falls eine IQ-Wallbox vorhanden ist. Die Spec beschreibt diese Antworten nur als Schema ohne Beispiele.

| Endpunkt | Bezeichnung | Felder |
|---|---|---|
| `GET /api/v4/systems/{system_id}/ev_charger/devices` | Aktive Wallboxen | `total_devices` · `devices` |
| `GET /api/v4/systems/{system_id}/ev_charger/events` | Ereignisse (`offset`, `limit`, `serial_num`) | — |
| `GET /api/v4/systems/{system_id}/ev_charger/{serial_no}/sessions` | Ladevorgänge | `sessions[]`: `start_time`/`end_time` · `duration` (s) · `energy_added` (Wh) · `charge_time` · `miles_added` · `cost` |
| `GET /api/v4/systems/{system_id}/ev_charger/{serial_no}/schedules` | Ladezeitpläne | — |
| `GET /api/v4/systems/{system_id}/ev_charger/{serial_no}/lifetime` | Tagesenergie (`YYYYMMDD`) | `consumption` (Wh) |
| `GET /api/v4/systems/{system_id}/ev_charger/{serial_no}/telemetry` | 15-min-Energie | `consumption[]`: `end_at`, `consumption` (Wh) |
| `POST …/start_charging` / `…/stop_charging` | Laden starten/stoppen — laut Spec "illustrative only", nur über VPP-API für Partner | — |

## Statuswerte (`status`)

Laut Filter-Enum von `/systems/search`: `normal`, `comm` (Kommunikationsproblem), `micro` (Wechselrichter-Problem), `power`, `meter`, `meter_issue`, `battery`, `storage_idle`, `encharge`, `encharge_issue`, `enpower`, `enpower_issue`. Die Zuordnung zu den Enlighten-Anzeigetexten steht nur im Portal, nicht in der Spec.

## Zeitfenster-Regeln der Telemetrie-Endpunkte

| Regel | Wert |
|---|---|
| Default-Start | Mitternacht heute in der Zeitzone der Anlage |
| `end_at` | min(Request-Zeitpunkt, `start_at` + `granularity`) |
| Max. Intervalle | `15mins` → 1 (Mikro: 3), `day` → 96 × 15 min (Mikro: 288 × 5 min), `week` → 672 × 15 min |
| Max. Rückblick | `start_at` höchstens 2 Jahre zurück |
| `rgm_stats` | max. 7 Tage je Abruf, Startzeit wird auf 15-min-Raster abgerundet |

**Hinweis Dashboard-Relevanz (Wärmepumpe):** Für PV-Überschuss/Eigenverbrauch der Wärmepumpe reichen voraussichtlich `latest_telemetry` (Momentwerte Produktion/Verbrauch) und `telemetry/production_meter` + `telemetry/consumption_meter` + `energy_import/export_telemetry` (15-min-Zeitreihen). Wegen des knappen Minuten-/Monatskontingents sollte das Polling-Intervall an der 15-min-Auflösung der Zähler-Telemetrie ausgerichtet werden, nicht am Viessmann-Takt.
