# UN-Nummern Sammler

Kleine Flutter-App zum sammeln von UN-Nummern.
Die Idee hatte ich auf einer Autofahrt während ich mit dem Kennzeichensammler Kennzeichen gesammelt habe.

Wenn ihr Feedback oder Bugs findet: DM **inqsane** auf discord.

## Hinweis zu Bug Reporting / Feedback:
- Bitte Datenbankenfehler sofort melden, z.b. wenn eine Klasse falsch eingetragen ist.
- Bitte Übersetzungsfehler (Ja ich arbeite an einer deutschen Übersetzung) sofort melden.
- Bitte Formatierungsfehler (Sowohl auf Github als auch in der App) bitte melden.
- Alles was in Zusammenhang mit einer UN Nummer steht bezieht sich auf die Datenbank, das bitte beachten.

## Features
- Suche nach UN-Nummern (4-stellig, z.B. `0001` oder `0023`)
- Datenquelle: `assets/un_with_class.json`
- Einstellungen ig

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
