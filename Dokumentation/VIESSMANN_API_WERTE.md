# Viessmann API — verfügbare Werte

Vollständige Liste aller Feature-/Property-Kombinationen, die über die Viessmann IoT API für dieses Gerät tatsächlich beobachtet wurden — nicht aus der offiziellen Dokumentation abgeschrieben, sondern direkt aus den seit Phase 1 gesammelten Rohdaten extrahiert (Stand 2026-09-22, 25.547 Messwerte, 355 unterschiedliche Feature/Property-Kombinationen, Gerät `Vitocal250A`).

**Wie zu lesen:** Jede Zeile einer Tabelle ist ein *Feature* (der `heating.…`/`device.…`/`tcu.…`-Schlüssel, wie er auch in `FeatureSample.featureName` steht). Die Spalte "Eigenschaften" listet dessen *Properties* (`FeatureSample.propertyKey`) mit Einheit und einem echten Beispielwert aus den gesammelten Daten. Wiederkehrende indizierte Features (z. B. pro Heizkreis) sind mit `N` als Platzhalter zusammengefasst, wenn mehrere Instanzen strukturell identisch sind.

Diese Liste ist eine Momentaufnahme dessen, was **dieses** Gerät liefert — andere Wärmepumpen-Modelle oder Firmware-Stände können abweichen (mehr/weniger Heizkreise, andere optionale Features).

## Heizkreise

Bei diesem Gerät: `N=0` → "Heizkörper", `N=1` → "Fussbodenheizung".

| Feature-Key | Bezeichnung | Eigenschaften |
|---|---|---|
| `heating.circuits` | Heizkreis (Übersicht) | `enabled`: welche Indizes existieren (z. B. "0,1") · `internal`: "0" |
| `heating.circuits.N` | Heizkreis N | `active`: 1.0 · `name`: "Heizkörper" · `type`: "heatingCircuit" |
| `heating.circuits.N.name` | Heizkreis-Name | `name`: "Heizkörper" |
| `heating.circuits.N.circulation.pump` | Heizkreispumpe | `status`: "off" |
| `heating.circuits.N.frostprotection` | Frostschutz | `status`: "off" |
| `heating.circuits.N.zone.mode` | Zone · Mode | `active`: 0.0 |
| `heating.circuits.N.sensors.temperature.supply` | Vorlauftemperatur | `status`: "connected" · `value` (celsius): 21.4 |
| `heating.circuits.N.temperature` | Temperatur (aktuell) | `value` (celsius): 0.0 |
| `heating.circuits.N.temperature.levels` | Temperatur-Grenzen | `min`/`max` (celsius): 20.0 / 60.0 |
| `heating.circuits.N.heating.curve` | Heizkurve | `slope` (Steigung): 1.1 · `shift` (Verschiebung): 0.0 |
| `heating.circuits.N.heating.schedule` | Heizzeitplan | `active`: 0.0 · `entries`: Zeitplan-Einträge |
| `heating.circuits.N.configuration.summerEco.absolute` | Sommer-Eco-Schwelle | `active`: 1.0 · `threshold` (celsius): 23.0 |
| `heating.circuits.N.operating.modes.active` | Betriebsmodus | `value`: "standby" |
| `heating.circuits.N.operating.modes.heating` / `.standby` | Modus-Einzelstatus | `active`: 0.0 / 1.0 |
| `heating.circuits.N.operating.programs.active` | Aktives Programm | `value`: "standby" |
| `heating.circuits.N.operating.programs.standby` / `.fixed` / `.frostprotection` / `.forcedLastFromSchedule` / `.summerEco` | Programm-Einzelstatus (ohne weitere Werte) | `active`: 0.0/1.0 |
| `heating.circuits.N.operating.programs.comfortHeating` / `.normalHeating` / `.reducedHeating` | Heiz-Programme mit Solltemperatur | `active` · `demand`: "heating" · `temperature` (celsius): z. B. 22.0 / 20.0 / 10.0 |
| `heating.circuits.N.operating.programs.comfortEnergySaving` / `.normalEnergySaving` / `.reducedEnergySaving` | Energiespar-Programme | `active` · `demand`: "heating" · `reason`: "summerEco"/"unknown" |
| `heating.circuits.N.operating.programs.comfortCoolingEnergySaving` / `.normalCoolingEnergySaving` / `.reducedCoolingEnergySaving` | Kühlungs-Energiespar-Programme | `active` · `demand`: "cooling" · `reason`: "summerEco" |

## Warmwasser

| Feature-Key | Bezeichnung | Eigenschaften |
|---|---|---|
| `heating.dhw` | Warmwasser (Übersicht) | `active`: 1.0 · `status`: "on" |
| `heating.dhw.sensors.temperature.hotWaterStorage` | Warmwassertemperatur (Speicher) | `status`: "connected" · `value` (celsius): 49.9 |
| `heating.dhw.sensors.temperature.dhwCylinder` | Temperatur Warmwasserspeicher (Zylinder) | `status` · `value` (celsius): 49.9 |
| `heating.dhw.temperature.main` | Warmwasser-Solltemperatur | `value` (celsius): 50.0 |
| `heating.dhw.temperature.levels` | Warmwasser-Temperaturgrenzen | `default`/`min`/`max` (celsius): 50.0 / 10.0 / 10.0 |
| `heating.dhw.temperature.hysteresis` | Schalthysterese | `value`, `switchOnValue`, `switchOffValue` (kelvin): 7.0 / 7.0 / 1.5 |
| `heating.dhw.operating.modes.active` | Aktiver Warmwasser-Modus | `value`: "efficient" |
| `heating.dhw.operating.modes.efficient` / `.efficientWithMinComfort` / `.off` | Modus-Einzelstatus | `active`: 0.0/1.0 |
| `heating.dhw.pumps.circulation` | Zirkulationspumpe | `status`: "on" |
| `heating.dhw.pumps.circulation.schedule` | Zirkulations-Zeitplan | `active`: 1.0 · `entries` |
| `heating.dhw.schedule` | Warmwasser-Zeitplan | `active`: 1.0 · `entries` |
| `heating.dhw.hygiene` | Hygiene-Funktion | `enabled`: 0.0 |
| `heating.dhw.oneTimeCharge` | Einmalige Aufladung | `active`: 0.0 |
| `heating.dhw.scaldProtection` | Verbrühschutz | `active`: 1.0 |

## Wärmepumpe (Kältekreis: Verdichter, Verdampfer, Kondensator, Wechselrichter)

| Feature-Key | Bezeichnung | Eigenschaften |
|---|---|---|
| `heating.compressors` | Verdichter (Übersicht) | `enabled`: welche Indizes existieren |
| `heating.compressors.N` | Verdichter N | `active`: 0.0 · `phase`: "ready" |
| `heating.compressors.N.statistics` | Verdichter-Statistik | `hours` (hour): 4434.0 · `starts`: 3659.0 |
| `heating.compressors.N.speed.current` / `.setpoint` | Verdichter-Drehzahl | `value` (revolutionsPerSecond): 0.0 |
| `heating.compressors.N.heater.crankcase` | Kurbelwannenheizung | `active`: 0.0 |
| `heating.compressors.N.sensors.pressure.inlet` | Verdichter-Ansaugdruck | `status` · `value` (bar): 7.54 |
| `heating.compressors.N.sensors.temperature.inlet` / `.outlet` / `.oil` / `.motorChamber` | Verdichter-Temperaturen | `status` · `value` (celsius): 18.4 / 19.5 / 19.6 / 18.8 |
| `heating.evaporators.N.sensors.temperature.liquid` / `.overheat` | Verdampfer-Temperaturen | `status` · `value` (celsius): 18.0 / 19.6 |
| `heating.evaporators.N.heater.base` | Verdampfer-Heizung | `active`: 0.0 |
| `heating.condensors.N.sensors.temperature.liquid` | Kondensator-Temperatur | `status` · `value` (celsius): 20.9 |
| `heating.economizers.N.sensors.temperature.liquid` | Economizer-Temperatur | `status` · `value` (celsius): 20.7 |
| `heating.inverters.N.sensors.temperature.powerModule` | Wechselrichter-Temperatur | `status` · `value` (celsius): 23.1 |
| `heating.inverters.N.sensors.power.current` | Wechselrichter-Strom | `status` · `value` (ampere): 0.0 |
| `heating.inverters.N.sensors.power.output` | Wechselrichter-Leistung | `status` · `value` (watt): 0.0 |
| `heating.outdoor.defrosting` | Abtauung (Außeneinheit) | `active`: 0.0 |
| `heating.primaryCircuit.sensors.temperature.supply` | Primärkreis-Vorlauf | `status` · `value` (celsius): 15.7 |
| `heating.primaryCircuit.fans.N.current` | Primärkreis-Lüfterdrehzahl | `status` · `value` (percent): 0.0 |
| `heating.primaryCircuit.valves.fourThreeWay` | Primärkreis-4/3-Wege-Ventil | `active`: 0.0 |
| `heating.secondaryCircuit.sensors.temperature.supply` | Sekundärkreis-Vorlauf | `status` · `value` (celsius): 25.9 |
| `heating.secondaryCircuit.temperature.return.minimum` | Sekundärkreis-Rücklauf-Minimum | `value` (celsius): 5.0 |
| `heating.secondaryCircuit.valves.fourThreeWay` | Sekundärkreis-4/3-Wege-Ventil | `current`/`target` (percent): 50.0 / 50.0 |
| `heating.secondaryCircuit.operation.state` | Sekundärkreis-Betriebsstatus | `currentValue`/`targetValue`: "standby" |
| `heating.secondaryHeatGenerator` | Sekundärer Wärmeerzeuger | `active`: 0.0 · `connectionType`: "unknown" |
| `heating.valves.fourThreeWay.position` | 4/3-Wege-Ventil-Position | `value`: "climatCircuitTwoDefrost" |

## Kessel & Wärmeerzeugung / Zusatzheizung

| Feature-Key | Bezeichnung | Eigenschaften |
|---|---|---|
| `heating.boiler.sensors.temperature.commonSupply` | Vorlauftemperatur (gemeinsam) | `status` · `value` (celsius): 25.5 |
| `heating.boiler.temperature.current` | Kesseltemperatur | `value` (celsius): 0.0 |
| `heating.boiler.pumps.internal` | Kesselpumpe | `status`: "off" |
| `heating.boiler.pumps.internal.current` / `.target` | Kesselpumpen-Leistung | `value` (percent): 0.0 / 0.0 |
| `heating.boiler.serial` | Kessel-Seriennummer | `value`: "7975116312054120" |
| `heating.buffer.sensors.temperature.main` / `heating.bufferCylinder.sensors.temperature.main` | Puffer-/Pufferzylinder-Temperatur | `status` · `value` (celsius): 21.4 |
| `heating.heat.production.current` | Aktuelle Wärmeleistung | `status` · `value` (kilowatt): 0.0 |
| `heating.heat.production.summary.heating` / `.dhw` / `.cooling` | Wärmemenge nach Zweck (Tag/Monat/Jahr) | `currentDay`/`currentMonth`/`currentYear`/`lastMonth`/`lastSevenDays`/`lastYear` (kilowattHour) — siehe Effizienz-Tab |
| `heating.heater.condensatePan` | Kondensatwannenheizung | `active`: 0.0 |
| `heating.heater.fanRing` | Lüfterring-Heizung | `active`: 0.0 |
| `heating.heatingRod` | Heizstab (Übersicht) | `active`: 1.0 |
| `heating.heatingRod.statistics` | Heizstab-Statistik | `hours` (hour): 76.0 · `starts`: 1936.0 |
| `heating.heatingRod.power.consumption.summary.heating` / `.dhw` | Heizstab-Stromverbrauch nach Zweck | `currentDay`/…/`lastYear` (kilowattHour) — **bewusst nicht** in der Effizienz-Berechnung berücksichtigt (siehe Backlog) |
| `heating.external.lock` | Externe Sperre | `active`: 0.0 |

## Allgemeine Sensoren

| Feature-Key | Bezeichnung | Eigenschaften |
|---|---|---|
| `heating.sensors.temperature.outside` | Außentemperatur | `status` · `value` (celsius): 16.8 |
| `heating.sensors.temperature.return` | Rücklauftemperatur | `status` · `value` (celsius): 25.8 |
| `heating.sensors.temperature.allengra` | Temperatur "Allengra" (Herstellerintern) | `status` · `value` (celsius): 26.3 |
| `heating.sensors.pressure.supply` | **Anlagendruck (Wasserdruck)** | `status` · `value` (bar): 1.7 — Datenquelle für die geplante Wasserdruck-Überwachung |
| `heating.sensors.volumetricFlow.allengra` | Volumenstrom "Allengra" | `status` · `value` (liter/hour): 0.0 |
| `heating.sensors.valve.N.expansion.target` | Expansionsventil-Sollstellung | `value` (percent): 50.0 / 0.0 |

## Stromverbrauch & Effizienz

Ausführlich dokumentiert im Effizienz-Tab-Backlog-Eintrag; hier die Rohdaten-Übersicht.

| Feature-Key | Bezeichnung | Eigenschaften |
|---|---|---|
| `heating.power.consumption.current` | Aktuelle elektrische Leistung | `status` · `value` (kilowatt): 0.0 |
| `heating.power.consumption.summary.heating` / `.dhw` / `.cooling` | Stromverbrauch nach Zweck, vorberechnete Fenster **(verlässlich befüllt)** | `currentDay`/`currentMonth`/`currentYear`/`lastMonth`/`lastSevenDays`/`lastYear` (kilowattHour) |
| `heating.power.consumption.heating` / `.dhw` / `.total` | Stromverbrauch als Zeitreihen-Arrays **(echte Historie, siehe unten)** | `day`/`week`/`month`/`year` (kilowattHour, Array von Zahlen) · `dayValueReadAt`/`weekValueReadAt`/`monthValueReadAt`/`yearValueReadAt` (Zeitstempel) |
| `heating.scop.heating` / `.dhw` / `.total` | Von Viessmann berechnete saisonale Effizienz (Seasonal COP) | `value`: 4.3 / 3.2 / 3.8 |
| `heating.spf.heating` / `.dhw` / `.total` | Von Viessmann berechnete saisonale Effizienz (Seasonal Performance Factor, identisch zu SCOP bei diesem Gerät) | `value`: 4.3 / 3.2 / 3.8 |

**Hinweis zu `heating.power.consumption.heating/.dhw/.total`:** Entgegen der ursprünglichen Vermutung sind diese Werte weder leer noch kommagetrennte Strings — sie kommen als echtes JSON-Zahlenarray und werden von unserem `FeatureValue`-Decoder schon korrekt als `.numberArray([Double])` gelesen, ohne Decoder-Änderung nötig. Am 2026-10-11 live beobachtet (`heating.power.consumption.dhw`):
`day`: 8 Werte, `[0]` = heutiger Tag (identisch mit `summary.dhw.currentDay`), `[1…7]` = die letzten 7 Tage absteigend.
`week`: 5 Werte, `[0]` = aktuelles 7-Tage-Fenster (identisch mit `summary.dhw.lastSevenDays`), `[1…4]` = die vier vorherigen 7-Tage-Fenster (keine Kalenderwochen, einfach 7-Tage-Blöcke rückwärts).
`month`: 13 Werte, `[0]` = laufender Monat (identisch mit `summary.dhw.currentMonth`), `[1]` = letzter abgeschlossener Monat (identisch mit `summary.dhw.lastMonth`), `[2…12]` weitere 11 Monate zurück.
`year`: 2 Werte, `[0]` = laufendes Jahr (identisch mit `summary.dhw.currentYear`), `[1]` = Vorjahr (identisch mit `summary.dhw.lastYear`).
`.total` ist rechnerisch die Summe aus `.heating` + `.dhw` + `.cooling` auf jedem Index (geprüft). Die `.summary.*`-Variante bleibt die einfachste Quelle für den jeweils aktuellen Einzelwert, aber `.heating`/`.dhw`/`.total` liefern jetzt zusätzlich die Historie dahinter.

**Kein Pendant für Wärmemenge:** `heating.heat.production.heating` und `heating.heat.production.total` existieren auf diesem Gerät **nicht** (Stand 2026-10-11, live geprüft) — nur `heating.heat.production.summary.heating`/`.dhw`/`.cooling` mit den Rollwerten. Für die erzeugte Wärmemenge gibt es also keine API-Zeitreihe, nur die App-eigenen Snapshots (`HeatPumpEfficiencySample`).

## Konfiguration & Anlagenparameter

Statische/selten ändernde Werte, die die Anlage selbst beschreiben.

| Feature-Key | Bezeichnung | Eigenschaften |
|---|---|---|
| `heating.configuration.pressure.total` | Druck-Referenzwerte | `defaultPressure` (bar): 1.5 · `normalPressureDelta` (bar): 0.6 · `maximumPressure` (bar): 2.7 · `errorThreshold` (bar): 3.5 |
| `heating.configuration.houseLocation` | Standort des Hauses | `latitude`/`longitude` (degree) · `altitude` (meter) |
| `heating.configuration.houseOrientation` | Ausrichtung des Hauses | `horizontal`/`vertical` (degree) |
| `heating.configuration.houseHeatingLoad` | Heizlast des Hauses | `value` (kilowattHour/year): 0.0 |
| `heating.configuration.temperature.outside.DampingFactor` | Dämpfungsfaktor Außentemperatur | `value` (minute): 10.0 |
| `heating.configuration.internalPumpOne` / `.internalPumpTwo` / `.internalPumps` | Interne Pumpen-Grenzwerte | `defaultLimit`/`minimumLimit`/`maximumLimit` (percent) |
| `heating.configuration.bufferCylinderSize` / `.centralHeatingCylinderSize` / `.dhwCylinderSize` | Speichergrößen | `value` (liter): 0.0 (bei diesem Gerät nicht konfiguriert) |
| `heating.configuration.heatingRod.heating` / `.dhw` | Heizstab-Freigabe je Zweck | `useApproved`: 0.0 |
| `heating.device.variant` | Geräte-Variante (Heizungs-Namespace-Duplikat von `device.variant`) | `value`: "Vitocal250A" |

## Betriebsprogramme (anlagenweit)

| Feature-Key | Bezeichnung | Eigenschaften |
|---|---|---|
| `heating.operating.programs.holiday` | Urlaubsprogramm | `active`: 0.0 · `start`/`end` |
| `heating.operating.programs.holidayAtHome` | "Urlaub zu Hause"-Programm | `active`: 0.0 · `start`/`end` (Default: "2000-01-01") |

## Gerät / System

| Feature-Key | Bezeichnung | Eigenschaften |
|---|---|---|
| `device.serial` | Seriennummer | `value`: "7975116312054120" |
| `device.brand` | Marke | `value`: "Viessmann" |
| `device.type` | Gerätetyp | `value`: "mono" |
| `device.variant` | Geräte-Variante | `value`: "Vitocal250A" |
| `device.productIdentification` / `.productMatrix` | Produktkennung/-matrix | `product` (bei diesem Gerät leer) |
| `device.parameterIdentification.version` | Firmware-/Parameterversion | `value`: "0030.0516.2501.0058" |
| `device.time.daylightSaving` | Sommerzeit-Umstellung | `active`: 1.0 · `begin`/`end`: "25-03" / "25-10" |
| `device.configuration.houseLocation` | Standort (Geräte-Namespace, nur Höhe) | `altitude` (meter): 0.0 |
| `device.actorSensorTest` | Aktor-/Sensor-Selbsttest | `active`: 0.0 · `status`: "standby" |
| `device.lock.external` / `.malfunction` | Sperrzustände | `active`: 0.0 |
| `device.zigbee.active` / `.status` | Zigbee-Modul | `active`: 1.0 · `status`: "connected" |
| `device.power.consumption.limitation` | Leistungsbegrenzung Verbrauch | `value`: "14aOff" (§14a-EnWG-Steuerung, deaktiviert) |
| `device.power.statusReport.consumption` / `.production` | Status der Leistungsregelung | `limit` (watt) · `status`: "unlimitedAutonomous" / "init" |

## Meldungen

| Feature-Key | Bezeichnung | Eigenschaften |
|---|---|---|
| `device.messages.info.raw` | Info-Meldungen | `entries` (Liste, bei diesem Gerät aktuell leer) |
| `device.messages.service.raw` | Service-Meldungen | `entries` (Liste, aktuell leer) |
| `device.messages.status.raw` | Statusmeldungen | `entries` (Liste, aktuell leer) |

## Netzwerk

| Feature-Key | Bezeichnung | Eigenschaften |
|---|---|---|
| `tcu.wifi` | WLAN-Verbindung (Gateway) | `strength`: Signalstärke, z. B. -24.0 |

**Hinweis:** Weitere Gateway-/Netzwerk-Features (`tcu.ethernet`, `tcu.features.*` etc.) wurden früher in dieser Session beobachtet, stammten aber vom fälschlich abgefragten Gateway-Pseudogerät (siehe Fix "Falsches Gerät wurde gepollt" im Backlog) und sind auf dem tatsächlichen Wärmepumpen-Gerät nicht vorhanden. Diese Liste enthält nur, was das korrekte Gerät (`deviceId: "0"`) liefert.
