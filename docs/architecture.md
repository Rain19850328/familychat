# 폐쇄형 가족 채팅 설계 메모

## 1. 반드시 지켜야 할 경계

- 테넌트 단위는 `family`
- 모든 사용자, 초대 코드, 방, 메시지, 첨부는 하나의 `family_id`에 소속
- 서버는 요청마다 `session.family_id === target.family_id`를 검증
- 가족 외 대상을 찾는 검색 API는 만들지 않음

## 2. 권한

- `admin`
  - 가족 그룹 생성
  - 초대 코드 발급/폐기
  - 가족 설정 관리
- `member`
  - 가족 전체방 참여
  - 가족 내부 1:1 참여
  - 메시지/이미지 송수신

일반 사용자의 관리자 승격 UI/API는 두지 않는다.

## 3. 방 모델

- `family`: 가족 전체 공용방 1개
- `dm`: 가족 내부 1:1
- `group`: 차기 확장. 같은 가족 내부 소규모 그룹방

DM 생성 규칙:

- `family_id`가 같은 두 멤버 쌍만 허용
- 유일 키는 `family_id + sorted(member_ids)`

## 4. 추천 테이블

- `families`
- `members`
- `invites`
- `rooms`
- `room_members`
- `messages`
- `attachments`
- `read_receipts`
- `device_sessions`
- `room_notification_settings`

## 5. API 스케치

- `POST /api/families`
- `POST /api/invites`
- `POST /api/auth/join`
- `POST /api/auth/login`
- `GET /api/rooms`
- `GET /api/rooms/:roomId/messages`
- `POST /api/rooms/:roomId/messages`
- `POST /api/rooms/dm`
- `POST /api/uploads/image`
- `POST /api/rooms/:roomId/read`
- `POST /api/rooms/:roomId/mute`

각 API는 세션의 `family_id`와 대상 리소스의 `family_id`가 다르면 `403`으로 거절한다.

## 6. 실시간

- MVP: 가족 단위 Durable Object 또는 WebSocket hub
- 연결 후 서버는 세션의 `family_id`에 해당하는 이벤트만 구독 허용
- 방 진입/메시지 수신/읽음 처리 모두 가족 범위를 벗어나지 않도록 필터링

## 7. PWA

- 앱 셸 캐시
- 최근 메시지 로컬 캐시
- 오프라인 시 캐시된 화면 유지
- 온라인 복귀 시 미전송 큐 재전송
- Web Push는 브라우저 지원 범위에 따라 선택 제공
