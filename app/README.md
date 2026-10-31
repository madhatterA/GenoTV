# `app`

The GenoTV application: the runner projects for each platform (`android/`, `ios/`,
`macos/`, `tvos/`, `windows/`) and the Dart code that starts the app.

`app/lib/composition.dart` builds the app: it creates the services from the packages in
`../packages/` and connects them to the user interface. Most features live in those
packages; this folder only wires them together and holds platform settings, icons and
signing configuration.

## Run

```bash
flutter pub get
flutter run
```
