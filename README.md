# Project Ledger

A Flutter ledger app targeting Windows desktop and the web.

## Run locally

```powershell
flutter pub get
flutter run -d windows
flutter run -d chrome
```

## Validate and build

```powershell
flutter analyze
flutter test
flutter build web
flutter build windows
```

Windows builds require Visual Studio with the **Desktop development with C++**
workload, CMake tools, and the Windows SDK. The project currently includes
only the Windows and web platform targets.
