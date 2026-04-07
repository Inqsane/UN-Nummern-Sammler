# UN-Nummern Sammler

Kleine Flutter-App zum sammeln von UN-Nummern.
Die Idee hatte ich auf einer Autofahrt während ich mit dem Kennzeichensammler Kennzeichen gesammelt habe.

Wenn ihr Feedback oder Bugs findet: DM **inqsane** auf discord.

## Hinweis zu Bug Reporting / Feedback:
- Bitte Datenbankenfehler sofort melden, z.b. wenn eine Klasse falsch eingetragen ist.
- Bitte Übersetzungsfehler (Ja ich arbeite an einer deutschen Übersetzung) sofort melden.
- Bitte Formatierungsfehler (Sowohl auf Github als auch in der App) bitte melden.
- Alles was in Zusammenhang mit einer UN Nummer steht bezieht sich auf die Datenbank, das bitte beachten.

## Bekannte Probleme

- Einige UN-Nummern werden nicht gefunden, wenn sie nicht in der lokalen JSON-Datenbank enthalten sind.
- Die Eingabe von UN-Nummern mit weniger als 4 Ziffern kann zu keinem Ergebnis führen (z.B. "1" statt "0001").
- Die automatische Erkennung von Unterklassen basiert auf Heuristiken und kann in Einzelfällen falsch sein.
- Manche Symbole werden nicht angezeigt, wenn die entsprechende Asset-Datei fehlt oder falsch benannt ist.
- Die Online-Suche hängt von externen Apps/Browsern ab und kann fehlschlagen, wenn keine verfügbar sind.
- Gespeicherte UN-Einträge werden lokal gespeichert; beim Löschen der App-Daten gehen diese verloren.
- Design- und Einstellungen können beim App-Start kurzzeitig zurückgesetzt erscheinen, bis sie geladen sind.
- Es gibt keinen Offline-Ersatz für fehlende oder unvollständige Datenbankeinträge.
- Aktuell werden nur englische Daten unterstützt, da die UN-Datenbank auf Englisch basiert.
- Die Performance kann bei sehr vielen gespeicherten UN-Einträgen leicht sinken.

## Voraussetzungen
- Flutter SDK installiert
- (Optional) Android Studio / VS Code

## Voraussetzungen für Android (APK):
- Mindest Android Version: Android 4.1
- Maximale Android Version: Android 16

## Projekt starten
```bash
flutter pub get
flutter run
1
```
## Projekt zu APK umwandeln
```bash
flutter clean
flutter pub get
flutter build apk --release
```

## Hinweis zum download auf Android:
- Die neuste APK findet man immer unter https://github.com/Inqsane/UN-Nummern-Sammler/releases

## Hinweis zur Eingabe
UN-Nummern sind **4-stellig**.  
Wenn du z.B. `1` suchst, musst du `0001` eingeben.

## Daten / JSON
Die UN-Daten liegen in:
- `assets/un_with_class.json` 

Falls du die Datei änderst, achte darauf, dass sie auch in der `pubspec.yaml` als Asset eingetragen ist.

## Lizenz
Aktuell keine spezielle Lizenz angegeben. Sollte etwas am Projekt verändert werden bitte das inqsane per discord mitteilen. Danke
