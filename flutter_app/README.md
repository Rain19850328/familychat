# FamilyChat Flutter Web

실제 배포되는 프런트엔드 앱입니다.

## 실행

```powershell
..\flutter-sdk\bin\flutter.bat pub get
..\flutter-sdk\bin\flutter.bat run -d chrome
```

## 빌드

```powershell
..\flutter-sdk\bin\flutter.bat build web --release
```

## 배포 경로

GitHub Actions가 `flutter_app/build/web` 를 Cloudflare Pages로 배포합니다.
