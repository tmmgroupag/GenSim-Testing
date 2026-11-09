# Direkte Bilanzausgabe der manuellen Fensterlüftung

Die Ausgabe verwendet die nativen EnergyPlus-Variablen
`Zone Ventilation Sensible Heat Loss Energy` und
`Zone Ventilation Sensible Heat Gain Energy`. Zwei `Meter:Custom` summieren
diese Werte ausschließlich für die von GenSim manuell belüfteten Zonen.
Es gibt keine Nachrechnung von Luftströmen, Temperaturen oder Wärmeanteilen.
Die vorherigen `Estimated`-Ausgaben und ihre EMS-Nachrechnung wurden entfernt.

## Voraussetzung: ausschließlich manuelle Zonenlüftung

Für **alle** manuell belüfteten Zonen darf kein zusätzliches
`ZoneVentilation:DesignFlowRate`- oder
`ZoneVentilation:WindandStackOpenArea`-Objekt vorhanden sein.
Auch ein ausgeschaltetes oder zeitlich getrennt betriebenes zweites Objekt
verhindert die Zuordnung: Die Prüfung bewertet die Modellstruktur.

Mechanische Lüftung über HVAC-Anlagen und separat modellierte Infiltration
werden dadurch nicht pauschal ausgeschlossen. Entscheidend ist, ob sie in
dieselbe `Zone Ventilation`-Bilanz eingehen.

Die Prüfung läuft in `set_meters_idf`, nachdem die Lüftungsobjekte angelegt
wurden. Bei Mischbetrieb in einer betroffenen Zone werden **beide manuellen
Zähler vollständig ausgelassen** und eine Warnung mit den konkurrierenden
Objektnamen protokolliert. Es wird weder eine Schätzung noch eine unvollständige
Teilsumme als manueller Gebäudelastgang ausgegeben. Die sonstigen
Simulationsergebnisse werden weiterhin erzeugt.

ZoneList-Verweise konkurrierender Lüftungsobjekte werden aufgelöst. Nicht
zuordenbare Verweise, AirflowNetwork und eine kombinierte Außenluftbilanz mit
`Quadrature` in den betroffenen Zonen führen ebenfalls zum Auslassen.
Manuelle Objekte werden am GenSim-Namenssuffix ` - Manual Ventilation` und
am Zeitplan `ManualVentilationSchedule` erkannt; sie müssen direkt auf Zonen
verweisen. Individuell umbenannte oder anders erzeugte Objekte werden nicht
automatisch als manuelle Lüftung erkannt.

## Workflow einstellen

In Excel die manuelle Fensterlüftung aktivieren und die zusätzliche
temperaturgesteuerte Fensterlüftung deaktivieren. Anschließend neu exportieren.

Bei direkter Bearbeitung einer OSW:

1. `add_internal_loads` mit den `manual_vent_sched_*`-Profilen beibehalten.
2. `inject_manual_ventilation_idf` mit dem gewünschten `air_changes` beibehalten.
3. Den Schritt `inject_zone_ventilation_idf` entfernen, sofern er dieselben
   Zonen versorgt. `include_window_ventilation` in `custom_export_params` für
   einen späteren Excel-Import auf `0` setzen.
4. `set_meters_idf` nach allen Änderungen an den Lüftungsobjekten ausführen.
5. Mit `results` die CSV-Dateien erzeugen.

Das Flag in `custom_export_params` allein deaktiviert bei direkter
OpenStudio-Ausführung keinen vorhandenen Measure-Schritt.
`Test/regression/base_workflow.osw` enthält ursprünglich beide Lüftungsarten
und erfüllt die Voraussetzung daher ohne Anpassung nicht.

Die `measure_paths` müssen auf den Measures-Ordner von **GenSim-Testing**
zeigen. Eine neue Simulation ist erforderlich; alte Ergebnisdateien werden
nicht nachträglich erweitert. Bestehende Lüftungsobjekte werden von der
Ausgabefunktion weder gelöscht noch verändert.

## CSV-Spalten

In `Normal`, `Debug` und `Reduced` werden bei erfüllten Voraussetzungen ergänzt:

- `METER MANUAL VENTILATION SENSIBLE HEAT LOSS ENERGY[Wh]`
- `METER MANUAL VENTILATION SENSIBLE HEAT GAIN ENERGY[Wh]`

Die Großschreibung entspricht dem bestehenden GenSim-Export für Zähler.
Bei `time_step = 4` stehen die Viertelstundenwerte in
`report_variables_ZoneTimestep.csv`. EnergyPlus liefert Joule, der vorhandene
Export wandelt in Wh pro Intervall um. Mittlere Leistung in W = Wh geteilt
durch die Intervalldauer in Stunden, bei 15 Minuten also Wh × 4.
Die Jahres- und optionalen flächenbezogenen Dateien enthalten die Werte ebenfalls.

Beide Spalten sind positive, getrennte Verlust-/Gewinnsummen. Sie enthalten
die nativen Zonenwerte; es werden keine zusätzlichen Zone-/ZoneGroup-
Multiplikatoren durch diese Erweiterung angewendet.

Die Lüftung bleibt vollständig in der simulierten Wärmebilanz enthalten.
Die zusätzliche Ausgabe darf **nicht nochmals zum Wärmebedarf addiert werden**.
Sie beschreibt den sensiblen Wärmeaustausch durch manuelle Lüftung, nicht
einen separat ermittelten zusätzlichen Heizenergiebedarf. Latente Wärme ist
nicht Bestandteil dieser beiden Spalten.

## Prüfstand und Quellen

Ruby-Syntax, JSON und Measure-Metadaten werden geprüft. Keine Builds, Tests oder
Simulationen ausgeführt; die Integration ist noch nicht durch einen
EnergyPlus-Simulationslauf validiert.

- [EnergyPlus: Lüftungsausgaben](https://energyplus.readthedocs.io/en/stable/guides/input-output-reference/1.17-group-airflow.html)
- [EnergyPlus: Custom Meters](https://energyplus.readthedocs.io/en/stable/guides/getting-started/9.2-custom-meters.html)
