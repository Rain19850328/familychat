# FamilyChat Flutter App

This app currently ships as Flutter Web, and now also includes an Android runner.

## Web

```powershell
..\flutter-sdk\bin\flutter.bat pub get
..\flutter-sdk\bin\flutter.bat run -d chrome
```

```powershell
..\flutter-sdk\bin\flutter.bat build web --release
```

## Android

The project now includes `flutter_app/android`.

Debug APK:

```powershell
..\flutter-sdk\bin\flutter.bat build apk --debug
```

Release APK:

```powershell
..\flutter-sdk\bin\flutter.bat build apk --release
```

Notes:

- Android SDK must be installed and configured with `ANDROID_HOME` or `ANDROID_SDK_ROOT`.
- The Android package name is `com.rain19850328.familychat`.
- Voice calling uses Agora and requires microphone permission on Android.

## Deployment

GitHub Actions deploys `flutter_app/build/web` to Cloudflare Pages.
