# Getrennter Lastgang der manuellen Fensterlüftung

Diese Erweiterung basiert auf dem lokalen GenSim-Stand `develop-2.17`,
Commit `f292501df7ceb97d641a70889064cc2970533b24`.

## Verwendung

Die vorhandene Measure `inject_manual_ventilation_idf` erzeugt automatisch
zwei zusätzliche Ausgaben. Bestehende OSW-Dateien benötigen keine neuen Argumente.
Der Workflow muss diese Reihenfolge enthalten:

1. `add_internal_loads`: erzeugt `ManualVentilationSchedule` aus den vier
   `manual_vent_sched_*`-Profilen (96 Viertelstundenwerte pro Tagestyp).
2. `inject_manual_ventilation_idf`: legt die manuelle Lüftung mit `air_changes`
   und die zugehörigen EMS-Diagnoseobjekte an.
3. `set_meters_idf`: fordert die zusätzlichen Ausgabevariablen an.
4. `results`: schreibt die Zeitreihen in die vorhandenen CSV-Dateien.

In Excel muss die manuelle Fensterlüftung aktiviert sein. Bei direkter Ausführung
einer OSW ist der Measure-Schritt selbst entscheidend; das Flag in
`custom_export_params` allein fügt keinen Schritt hinzu.

`Test/regression/base_workflow.osw` enthält bereits die benötigten Schritte und
ein manuelles Profil. Für die Verwendung des Forks muss dessen Measures-Ordner
über `measure_paths` beziehungsweise den GenSim-Pfad eingebunden werden.
Nicht die Measures des ursprünglichen Checkouts verwenden.

## Ausgaben und Einheiten

In den Ausgabeebenen `Normal`, `Debug` und `Reduced` werden ergänzt:

- `Manual Ventilation Estimated Sensible Heat Loss Energy[Wh]`
- `Manual Ventilation Estimated Sensible Heat Gain Energy[Wh]`

Beide Werte sind positiv und über die von der Measure erfassten Zonen summiert.
EnergyPlus liefert Joule; die vorhandene Results-Measure wandelt diese in Wh
pro Ausgabeintervall um. Bei `time_step = 4` stehen sie in
`report_variables_ZoneTimestep.csv` als Viertelstundenwerte.
Mittlere Leistung in W = Wh / Intervalldauer in Stunden, bei 15 Minuten also
Wh × 4. Die vorhandenen Jahres- und flächenbezogenen Exporte enthalten ebenfalls
die zusätzlichen Spalten.

Die bisherigen `Zone Ventilation ...`-Spalten bleiben die Gesamtwerte aller
ZoneVentilation-Objekte. Die neue manuelle Ausgabe ist ein darin enthaltener
Anteil und darf nicht nochmals zum Gesamtverlust addiert werden.

## Berechnung und Grenzen

Die rein lesende EMS-Nachrechnung verwendet je HVAC-Systemzeitschritt:

```
Volumenstrom = Zonenvolumen × Luftwechsel / 3600 × Profilwert
              × (A + B × abs(T_innen - T_aussen) + C × Windgeschwindigkeit)
Waermeenergie = Volumenstrom × Aussenluftdichte × cp(Aussenluft)
                × (T_innen - T_aussen) × Zeitschrittdauer
```

BLAST: A=0.606, B=0.03636, C=0.1177; DOE2: A=0, B=0, C=0.224;
sonst konstant: A=1, B=0, C=0. Die Nachrechnung übernimmt die Temperatur- und
Windgrenzen der von dieser Measure erzeugten Lüftungsobjekte. Temperatur und
Wind werden auf Zonenhöhe gelesen. Negative Luftwechsel werden abgelehnt.
Ein erneuter Aufruf der Measure im selben Modell wird mit einer Fehlermeldung
abgebrochen, damit weder Lüftung noch Diagnose doppelt angelegt werden.

**Es handelt sich um eine Schätzung, nicht um eine separat ausgelesene interne
EnergyPlus-Bilanz.** Die am Ende des Systemzeitschritts verfügbare Zonentemperatur
kann von der Temperatur abweichen, die der Solver vorher für den Luftstrom
verwendet hat. Besonders bei schnellen Temperaturänderungen und an
Schaltgrenzen können daher Unterschiede entstehen.

Die Berechnung gilt für die unveränderten natürlichen DesignFlowRate-Objekte
dieser Measure. Spätere Änderungen an deren Parametern, EMS-Luftstromsteuerung,
HybridVentilation, AirflowNetwork, abweichende lokale Außenluftfeuchte oder eine
andere Dichtebasis werden nicht nachgeführt. Wie bei den bisherigen summierten
Zonenvariablen werden keine zusätzlichen Zone-/ZoneGroup-Multiplikatoren
eingerechnet. Bei solchen Modellen ist die Diagnose nicht als vollständiger
Gebäudewert zu verwenden.

Latente Wärme und ein kausal zusätzlicher Heiz-/Kühlbedarf werden nicht
berechnet. Wärmespeicherung und Anlagenregelung können den tatsächlichen
Heizenergiebedarf zeitlich verschieben.

Referenzen:
- [EnergyPlus: Infiltration/Ventilation](https://energyplus.readthedocs.io/en/stable/guides/engineering-reference/8.3-infiltrationventilation.html)
- [EnergyPlus: EMS Application Guide](https://energyplus.readthedocs.io/en/stable/ems-application-guide/ems-application-guide.html)

## Prüfstand

Keine Builds, neuen Tests oder Simulationen ausgeführt. Die Funktion ist damit
noch nicht durch einen EnergyPlus-Simulationslauf validiert.
