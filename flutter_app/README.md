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

## Agora Voice Call

- 웹 통화는 `agora_rtc_engine` 와 `iris-web-rtc` 스크립트를 사용합니다.
- 실제 통화 연결에는 Supabase Edge Function `agora-token` 이 필요합니다.
