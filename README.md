# FamilyChat

초대 코드로만 연결되는 가족 전용 채팅 앱입니다. 현재 프런트엔드는 Flutter Web이고, 백엔드는 Supabase를 사용합니다.

## 구조

- `flutter_app`: 실제 서비스되는 Flutter Web 앱
- `supabase/migrations`: 데이터베이스 마이그레이션
- `supabase/functions`: Edge Function
- `.github/workflows`: Cloudflare Pages 및 Supabase 배포 워크플로

## 로컬 실행

저장소 루트에서:

```powershell
cd flutter_app
..\flutter-sdk\bin\flutter.bat pub get
..\flutter-sdk\bin\flutter.bat run -d chrome
```

릴리스 웹 빌드:

```powershell
cd flutter_app
..\flutter-sdk\bin\flutter.bat build web --release
```

## 배포

- 프런트엔드: `.github/workflows/cloudflare-pages-deploy.yml`
- DB 마이그레이션: `.github/workflows/supabase-deploy.yml`
- Edge Function: `.github/workflows/supabase-functions-deploy.yml`

`main` 브랜치에 푸시하면 Flutter Web 앱이 Cloudflare Pages로 배포됩니다.
