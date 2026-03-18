# FamilyChat PWA

초대 코드 기반의 가족 전용 채팅 PWA입니다.
이제 데이터 저장소는 브라우저 `localStorage` 대신 `Supabase Postgres`를 사용합니다.

## 반영된 내용

- `Supabase` 테이블 스키마 추가
- 가족 생성, 초대 코드 발급, 가족 참가, DM 생성, 메시지 전송, 읽음 처리, 무음 처리용 RPC 추가
- 프론트엔드 상태를 `Supabase snapshot` 기준으로 동기화하도록 변경
- 같은 가족 데이터 변경 시 `Supabase Realtime`으로 자동 새로고침
- 로컬에는 현재 세션과 저장된 프로필만 유지

## 파일

- `supabase/migrations/20260317130258_remote_schema.sql`
- `supabase.config.js`
- `app.js`

## 설정 방법

1. `supabase.config.js`에 프로젝트 URL과 anon key를 입력합니다.
2. 로컬 Supabase를 쓸 경우 Docker가 실행 중이어야 합니다.
3. 마이그레이션을 적용합니다.

```powershell
npx supabase db reset
```

4. 정적 서버로 앱을 실행합니다.

```powershell
npx serve .
```

## 참고

- 현재 이미지 첨부는 `Supabase Storage`가 아니라 메시지 테이블의 `image_data_url` 컬럼에 저장됩니다.
- 운영 환경에서는 이후 `Storage` 버킷으로 옮기는 편이 맞습니다.
- 현재 권한 모델은 MVP 수준입니다. 익명 `anon key`로 RPC를 호출할 수 있으므로, 운영 전에는 `RLS`와 인증 전략을 별도로 정리해야 합니다.
