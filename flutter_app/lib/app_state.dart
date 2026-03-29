import 'dart:async';
import 'dart:convert';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'platform/web_push.dart';
import 'voice_message_support.dart';

const String kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://csarhidurfxdmcworbtk.supabase.co',
);
const String kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNzYXJoaWR1cmZ4ZG1jd29yYnRrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4MTIwNTgsImV4cCI6MjA4OTM4ODA1OH0.AW7mIgO0M_qk3xjrLkATrHO__HWFozcTyxjEIf-rjr8',
);

const String _storageKey = 'familychat.flutter.closed.v1';
const List<String> presetAvatarKeys = <String>[
  'adult-man',
  'adult-woman',
  'boy',
  'girl',
  'sparkle-friend',
];

class FamilyChatAppState extends ChangeNotifier {
  FamilyChatAppState(this._prefs);

  final SharedPreferences _prefs;
  final SupabaseClient _supabase = Supabase.instance.client;

  AppSession? session;
  List<DeviceProfile> savedProfiles = <DeviceProfile>[];
  FamilySnapshot? family;

  bool isBootstrapping = true;
  bool isBusy = false;
  String? errorMessage;
  String? toastMessage;

  String? pendingImageDataUrl;
  String? pendingImageName;
  String? profileDraftName;
  String? profileDraftAvatarKey;
  String? profileDraftAvatarImageDataUrl;

  RealtimeChannel? _familyChannel;
  RtcEngine? _rtcEngine;
  AudioPlayer? _voiceLoopPlayer;
  AudioPlayer? _voiceCuePlayer;
  Timer? _presenceTimer;
  Timer? _refreshTimer;
  Timer? _refreshDebounceTimer;
  final List<_QueuedSend> _queuedSends = <_QueuedSend>[];
  bool _isDrainingSendQueue = false;
  bool _isRefreshingFamily = false;
  bool _refreshRequestedAfterCurrent = false;
  bool _isMarkingRoomRead = false;
  bool _markRoomReadRequested = false;
  bool _isSyncingPushSubscription = false;
  bool _readReceiptsActive = true;
  bool isVoiceCallConnecting = false;
  bool isVoiceCallJoined = false;
  bool isVoiceCallMuted = false;
  bool isVoiceCallAutoplayBlocked = false;
  String? voiceCallError;
  String? _registeredPushEndpoint;
  String? _registeredPushMemberId;
  String? _voiceCallRoomId;
  String? _voiceCallChannelName;
  String? _voiceCallAppId;
  int? _voiceCallUid;
  final Set<int> _voiceCallRemoteUids = <int>{};
  String? _dismissedIncomingVoiceCallKey;
  String? _acceptedVoiceCallOverlayKey;
  bool _isAcceptingIncomingVoiceCall = false;
  bool _isCurrentVoiceCallOutbound = false;
  bool _hasVoiceCallEverConnected = false;
  _VoiceLoopTone _currentVoiceLoopTone = _VoiceLoopTone.none;
  BrowserPushSetupResult? pendingPushHelp;
  PushNavigationIntent? _pendingPushNavigation =
      getPendingPushNavigationIntent();

  Future<void> bootstrap() async {
    _hydrateLocalState();
    isBootstrapping = false;
    notifyListeners();

    if (session != null) {
      await refreshFamily(skipErrorToast: true);
      _subscribeFamilyRealtime();
      _startPresenceTimer();
      _startRefreshTimer();
      unawaited(touchCurrentMember());
      unawaited(_syncPushSubscription());
    }
  }

  bool get hasSession => session != null;
  bool get isAdmin => currentMember?.role == 'admin';

  MemberRecord? get currentMember {
    final current = session;
    final snapshot = family;
    if (current == null || snapshot == null) {
      return null;
    }
    for (final member in snapshot.members) {
      if (member.id == current.memberId) {
        return member;
      }
    }
    return null;
  }

  RoomRecord? get activeRoom {
    final current = session;
    final snapshot = family;
    if (current == null || snapshot == null) {
      return null;
    }

    final desiredId = current.activeRoomId;
    if (desiredId != null) {
      for (final room in snapshot.rooms) {
        if (room.id == desiredId) {
          return room;
        }
      }
    }

    for (final room in snapshot.rooms) {
      if (room.type == 'family') {
        return room;
      }
    }

    return snapshot.rooms.isNotEmpty ? snapshot.rooms.first : null;
  }

  List<MessageRecord> get activeMessages {
    final room = activeRoom;
    final snapshot = family;
    if (room == null || snapshot == null) {
      return const <MessageRecord>[];
    }
    return snapshot.messages
        .where((message) => message.roomId == room.id)
        .toList();
  }

  bool get isActiveRoomVoiceCallActive => activeRoom?.voiceCallActive == true;

  bool get isActiveRoomVoiceCallJoined =>
      activeRoom != null &&
      _voiceCallRoomId == activeRoom!.id &&
      isVoiceCallJoined;

  bool get isActiveRoomVoiceCallConnecting =>
      activeRoom != null &&
      _voiceCallRoomId == activeRoom!.id &&
      isVoiceCallConnecting;

  bool get isActiveRoomVoiceCallMuted =>
      isActiveRoomVoiceCallJoined && isVoiceCallMuted;

  bool get isActiveRoomVoiceAutoplayBlocked =>
      activeRoom != null &&
      _voiceCallRoomId == activeRoom!.id &&
      isVoiceCallAutoplayBlocked;

  String? get activeRoomVoiceCallError =>
      activeRoom != null && _voiceCallRoomId == activeRoom!.id
      ? voiceCallError
      : null;

  int get activeRoomVoiceParticipantCount =>
      (isActiveRoomVoiceCallJoined ? 1 : 0) + _voiceCallRemoteUids.length;

  RoomRecord? get incomingVoiceCallRoom {
    final snapshot = family;
    final member = currentMember;
    if (snapshot == null || member == null) {
      return null;
    }

    final candidates =
        snapshot.rooms
            .where(
              (room) =>
                  room.voiceCallActive &&
                  room.voiceChannelName != null &&
                  room.voiceChannelName!.isNotEmpty &&
                  room.voiceCallStartedBy != null &&
                  room.voiceCallStartedBy != member.id &&
                  (_voiceCallRoomId != room.id ||
                      (!isVoiceCallJoined && !isVoiceCallConnecting)),
            )
            .toList()
          ..sort((left, right) {
            final leftStamp = left.voiceCallStartedAt ?? left.createdAt;
            final rightStamp = right.voiceCallStartedAt ?? right.createdAt;
            return rightStamp.compareTo(leftStamp);
          });

    for (final room in candidates) {
      if (_dismissedIncomingVoiceCallKey == _voiceCallSessionKey(room)) {
        continue;
      }
      return room;
    }
    return null;
  }

  MemberRecord? get incomingVoiceCallCaller {
    final snapshot = family;
    final room = incomingVoiceCallRoom;
    final callerId = room?.voiceCallStartedBy;
    if (snapshot == null || callerId == null) {
      return null;
    }
    return snapshot.members
        .where((member) => member.id == callerId)
        .firstOrNull;
  }

  RoomRecord? get voiceCallOverlayRoom {
    final incoming = incomingVoiceCallRoom;
    if (incoming != null) {
      return incoming;
    }

    final snapshot = family;
    if (snapshot == null) {
      return null;
    }

    final roomId = _voiceCallRoomId;
    if (roomId != null && (isVoiceCallJoined || isVoiceCallConnecting)) {
      final activeVoiceRoom = snapshot.rooms
          .where((item) => item.id == roomId)
          .firstOrNull;
      if (activeVoiceRoom != null && activeVoiceRoom.voiceCallActive) {
        return activeVoiceRoom;
      }
    }

    final acceptedKey = _acceptedVoiceCallOverlayKey;
    if (acceptedKey == null) {
      return null;
    }

    final pendingAcceptedRoom = snapshot.rooms
        .where((item) => _voiceCallSessionKey(item) == acceptedKey)
        .firstOrNull;
    if (pendingAcceptedRoom == null || !pendingAcceptedRoom.voiceCallActive) {
      return null;
    }

    final selectedForJoin =
        _isAcceptingIncomingVoiceCall &&
        session?.activeRoomId == pendingAcceptedRoom.id;
    return selectedForJoin ? pendingAcceptedRoom : null;
  }

  MemberRecord? get voiceCallOverlayCaller {
    final snapshot = family;
    final room = voiceCallOverlayRoom;
    final callerId = room?.voiceCallStartedBy;
    if (snapshot == null || callerId == null) {
      return null;
    }
    return snapshot.members
        .where((member) => member.id == callerId)
        .firstOrNull;
  }

  bool get hasIncomingVoiceCall => incomingVoiceCallRoom != null;

  bool get isVoiceCallOverlayIncoming =>
      voiceCallOverlayRoom != null &&
      incomingVoiceCallRoom?.id == voiceCallOverlayRoom?.id;

  bool get isAwaitingVoiceCallAnswer {
    return _isCurrentVoiceCallOutbound &&
        _voiceCallRoomId != null &&
        _voiceCallRemoteUids.isEmpty &&
        (isVoiceCallConnecting || isVoiceCallJoined);
  }

  void clearToast() {
    toastMessage = null;
    notifyListeners();
  }

  void clearPendingPushHelp() {
    pendingPushHelp = null;
  }

  Future<void> createFamily({
    required String familyName,
    required String adminName,
  }) async {
    await _runBusy(() async {
      final payload = await _rpcMap('app_create_family', <String, dynamic>{
        'p_family_name': familyName.trim(),
        'p_admin_name': adminName.trim(),
      });
      await _applyRemoteSession(RemoteSessionPayload.fromJson(payload));
    });
  }

  Future<void> joinFamily({
    required String inviteCode,
    required String memberName,
  }) async {
    await _runBusy(() async {
      final payload = await _rpcMap('app_join_family', <String, dynamic>{
        'p_invite_code': inviteCode.trim().toUpperCase(),
        'p_member_name': memberName.trim(),
      });
      await _applyRemoteSession(RemoteSessionPayload.fromJson(payload));
    });
  }

  Future<void> activateSavedProfile(DeviceProfile profile) async {
    session = AppSession(
      familyId: profile.familyId,
      memberId: profile.memberId,
      activeRoomId: null,
    );
    await _persistLocalState();
    notifyListeners();

    await refreshFamily();
    _subscribeFamilyRealtime();
    _startPresenceTimer();
    _startRefreshTimer();
    unawaited(touchCurrentMember());
    unawaited(_syncPushSubscription());
  }

  Future<void> refreshFamily({
    bool skipErrorToast = false,
    String reason = 'manual',
  }) async {
    final current = session;
    if (current == null) {
      return;
    }
    if (_isRefreshingFamily) {
      _refreshRequestedAfterCurrent = true;
      _logChatTrace(
        'family_refresh_skipped_busy',
        roomId: current.activeRoomId,
        details: <String, Object?>{'reason': reason},
      );
      return;
    }

    _refreshDebounceTimer?.cancel();
    _isRefreshingFamily = true;
    final stopwatch = Stopwatch()..start();
    _logChatTrace(
      'family_refresh_start',
      roomId: current.activeRoomId,
      details: <String, Object?>{'reason': reason},
    );
    try {
      final payload = await _rpcMap(
        'app_get_family_snapshot',
        <String, dynamic>{'p_family_id': current.familyId},
      );
      final snapshot = FamilySnapshot.fromJson(payload);
      final stillMember = snapshot.members.any(
        (member) => member.id == current.memberId,
      );
      if (!stillMember) {
        await _invalidateCurrentSession(
          removeCurrentProfile: true,
          toast: '가족에서 탈퇴되어 처음 화면으로 이동했습니다. 채팅과 구성원 정보는 초기화되었습니다.',
        );
        return;
      }
      final resolvedRoom = _resolveActiveRoomId(snapshot, current.activeRoomId);
      family = FamilySnapshot(
        id: snapshot.id,
        name: snapshot.name,
        createdAt: snapshot.createdAt,
        members: snapshot.members,
        rooms: snapshot.rooms,
        invites: snapshot.invites,
        messages: <MessageRecord>[
          ...snapshot.messages,
          ..._pendingMessagesForSnapshot(snapshot),
        ],
        settings: snapshot.settings,
      );
      _syncVoiceCallOverlayState();
      unawaited(_syncVoiceCallSoundState());
      session = current.copyWith(activeRoomId: resolvedRoom);
      _syncCurrentProfileFromSnapshot();
      await _persistLocalState();
      notifyListeners();
      await _applyPendingPushNavigationIfReady();
      if (resolvedRoom != null &&
          _hasUnreadMessages(snapshot, resolvedRoom, current.memberId)) {
        unawaited(markActiveRoomRead());
      }
    } catch (error) {
      if (_shouldInvalidateSession(error)) {
        await _invalidateCurrentSession(
          removeCurrentProfile: true,
          toast: '가족에서 탈퇴되어 처음 화면으로 이동했습니다. 채팅과 구성원 정보는 초기화되었습니다.',
        );
        return;
      }
      if (!skipErrorToast) {
        _setToast(_friendlyError(error, fallback: '가족 정보를 불러오지 못했습니다.'));
      }
    } finally {
      stopwatch.stop();
      _logChatTrace(
        'family_refresh_end',
        roomId: current.activeRoomId,
        details: <String, Object?>{
          'reason': reason,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'messageCount': family?.messages.length,
        },
      );
      _isRefreshingFamily = false;
      if (_refreshRequestedAfterCurrent) {
        _refreshRequestedAfterCurrent = false;
        _scheduleFamilyRefresh(immediate: true, reason: 'queued_after:$reason');
      }
    }
  }

  Future<void> selectRoom(String roomId) async {
    final current = session;
    if (current == null) {
      return;
    }
    if (_voiceCallRoomId != null &&
        _voiceCallRoomId != roomId &&
        (isVoiceCallConnecting || isVoiceCallJoined)) {
      await leaveVoiceCall();
    }
    session = current.copyWith(activeRoomId: roomId);
    await _persistLocalState();
    notifyListeners();
    await markActiveRoomRead();
  }

  Future<void> createInvite() async {
    final snapshot = family;
    final member = currentMember;
    if (snapshot == null || member == null) {
      return;
    }

    await _runBusy(() async {
      await _rpcMap('app_create_invite', <String, dynamic>{
        'p_family_id': snapshot.id,
        'p_admin_member_id': member.id,
      });
      await refreshFamily();
      _setToast('초대 코드를 생성했습니다.');
    });
  }

  Future<void> openDirectMessage(MemberRecord target) async {
    final snapshot = family;
    final member = currentMember;
    if (snapshot == null || member == null) {
      return;
    }

    await _runBusy(() async {
      final payload =
          await _rpcMap('app_get_or_create_dm_room', <String, dynamic>{
            'p_family_id': snapshot.id,
            'p_first_member_id': member.id,
            'p_second_member_id': target.id,
          });
      final roomId = payload['id'] as String;
      session = session?.copyWith(activeRoomId: roomId);
      await _persistLocalState();
      await refreshFamily();
      await markActiveRoomRead();
    });
  }

  Future<void> startDirectVoiceCall(MemberRecord target) async {
    await openDirectMessage(target);
    await startOrJoinVoiceCall();
  }

  Future<bool> sendMessage(String rawText, {DateTime? initiatedAt}) async {
    final snapshot = family;
    final member = currentMember;
    final room = activeRoom;
    if (snapshot == null || member == null || room == null) {
      return false;
    }

    final text = rawText.trim();
    final image = pendingImageDataUrl;
    final imageName = pendingImageName;
    final sendPressedAt = initiatedAt ?? DateTime.now();
    if (text.isEmpty && (image == null || image.isEmpty)) {
      _setToast('메시지나 이미지를 입력해 주세요.');
      return false;
    }
    _logChatTrace(
      'send_button_pressed',
      roomId: room.id,
      details: <String, Object?>{
        'textLength': text.length,
        'hasImage': image != null,
      },
    );

    final optimisticMessageId =
        'local-${DateTime.now().microsecondsSinceEpoch}';
    final optimisticMessage = MessageRecord(
      id: optimisticMessageId,
      roomId: room.id,
      familyId: snapshot.id,
      senderId: member.id,
      type: image != null ? 'image' : 'text',
      text: text,
      imageDataUrl: image,
      audioDataUrl: null,
      audioDurationMs: null,
      createdAt: DateTime.now(),
      readBy: <String, String>{member.id: DateTime.now().toIso8601String()},
    );
    final optimisticAppendedAt = DateTime.now();

    pendingImageDataUrl = null;
    pendingImageName = null;
    _appendOptimisticMessage(optimisticMessage);
    _logChatTrace(
      'send_optimistic_appended',
      messageId: optimisticMessage.id,
      roomId: room.id,
      details: <String, Object?>{
        'textLength': text.length,
        'hasImage': image != null,
        'queueDepth': _queuedSends.length + 1,
        'elapsedSinceClickMs': optimisticAppendedAt
            .difference(sendPressedAt)
            .inMilliseconds,
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logChatTrace(
        'send_optimistic_frame_committed',
        messageId: optimisticMessage.id,
        roomId: room.id,
        details: <String, Object?>{
          'elapsedSinceClickMs': DateTime.now()
              .difference(sendPressedAt)
              .inMilliseconds,
        },
      );
    });

    _queuedSends.add(
      _QueuedSend(
        familyId: snapshot.id,
        roomId: room.id,
        senderId: member.id,
        messageType: image != null ? 'image' : 'text',
        text: text,
        imageDataUrl: image,
        audioDataUrl: null,
        audioDurationMs: null,
        imageName: imageName,
        optimisticMessage: optimisticMessage,
        initiatedAt: sendPressedAt,
        optimisticAppendedAt: optimisticAppendedAt,
      ),
    );
    _logChatTrace(
      'send_enqueued',
      messageId: optimisticMessage.id,
      roomId: room.id,
      details: <String, Object?>{'queueDepth': _queuedSends.length},
    );
    _startSendQueue();
    return true;
  }

  Future<bool> sendVoiceMessage(
    Uint8List wavBytes, {
    required int durationMs,
    DateTime? initiatedAt,
  }) async {
    final snapshot = family;
    final member = currentMember;
    final room = activeRoom;
    if (snapshot == null || member == null || room == null) {
      return false;
    }
    if (wavBytes.isEmpty) {
      _setToast('음성 메시지를 녹음하지 못했습니다.');
      return false;
    }

    final sendPressedAt = initiatedAt ?? DateTime.now();
    _logChatTrace(
      'send_voice_button_pressed',
      roomId: room.id,
      details: <String, Object?>{'durationMs': durationMs},
    );
    final audioDataUrl = encodeAudioDataUrl(wavBytes);
    final optimisticMessageId =
        'local-${DateTime.now().microsecondsSinceEpoch}';
    final optimisticMessage = MessageRecord(
      id: optimisticMessageId,
      roomId: room.id,
      familyId: snapshot.id,
      senderId: member.id,
      type: 'audio',
      text: '',
      imageDataUrl: null,
      audioDataUrl: audioDataUrl,
      audioDurationMs: durationMs,
      createdAt: DateTime.now(),
      readBy: <String, String>{member.id: DateTime.now().toIso8601String()},
    );
    final optimisticAppendedAt = DateTime.now();

    _appendOptimisticMessage(optimisticMessage);
    _logChatTrace(
      'send_voice_optimistic_appended',
      messageId: optimisticMessage.id,
      roomId: room.id,
      details: <String, Object?>{
        'durationMs': durationMs,
        'elapsedSinceClickMs': optimisticAppendedAt
            .difference(sendPressedAt)
            .inMilliseconds,
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logChatTrace(
        'send_voice_optimistic_frame_committed',
        messageId: optimisticMessage.id,
        roomId: room.id,
        details: <String, Object?>{
          'elapsedSinceClickMs': DateTime.now()
              .difference(sendPressedAt)
              .inMilliseconds,
        },
      );
    });

    _queuedSends.add(
      _QueuedSend(
        familyId: snapshot.id,
        roomId: room.id,
        senderId: member.id,
        messageType: 'audio',
        text: '',
        imageDataUrl: null,
        audioDataUrl: audioDataUrl,
        audioDurationMs: durationMs,
        imageName: null,
        optimisticMessage: optimisticMessage,
        initiatedAt: sendPressedAt,
        optimisticAppendedAt: optimisticAppendedAt,
      ),
    );
    _startSendQueue();
    return true;
  }

  Future<void> pickComposerImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) {
      return;
    }
    if ((file.bytes?.length ?? 0) > 2 * 1024 * 1024) {
      _setToast('이미지는 2MB 이하만 허용됩니다.');
      return;
    }
    final bytes = file.bytes;
    if (bytes == null) {
      _setToast('이미지를 읽지 못했습니다.');
      return;
    }
    final mimeType = file.extension == null
        ? 'image/png'
        : 'image/${file.extension}';
    pendingImageDataUrl = _toDataUrl(bytes, mimeType);
    pendingImageName = file.name;
    notifyListeners();
  }

  void clearPendingImage() {
    pendingImageDataUrl = null;
    pendingImageName = null;
    notifyListeners();
  }

  void setReadReceiptsActive(bool isActive) {
    if (_readReceiptsActive == isActive) {
      return;
    }
    _readReceiptsActive = isActive;
    _logChatTrace(
      'read_receipt_gate_changed',
      details: <String, Object?>{'isActive': isActive},
    );
    if (isActive) {
      unawaited(markActiveRoomRead(reason: 'focus_regained'));
    }
  }

  Future<void> markActiveRoomRead({String reason = 'unspecified'}) async {
    final snapshot = family;
    final member = currentMember;
    final room = activeRoom;
    if (snapshot == null || member == null || room == null) {
      return;
    }
    if (!_readReceiptsActive) {
      _logChatTrace(
        'read_receipt_skipped_inactive',
        roomId: room.id,
        details: <String, Object?>{'reason': reason},
      );
      return;
    }
    if (!_hasUnreadMessages(snapshot, room.id, member.id)) {
      return;
    }
    if (_isMarkingRoomRead) {
      _markRoomReadRequested = true;
      return;
    }

    _isMarkingRoomRead = true;
    _markRoomReadLocally(room.id, member.id);
    try {
      _logChatTrace(
        'read_receipt_start',
        roomId: room.id,
        details: <String, Object?>{'reason': reason},
      );
      await _rpcVoid('app_mark_room_read', <String, dynamic>{
        'p_room_id': room.id,
        'p_member_id': member.id,
      });
      _logChatTrace(
        'read_receipt_complete',
        roomId: room.id,
        details: <String, Object?>{'reason': reason},
      );
    } catch (_) {
      // Ignore read marker failures.
    } finally {
      _isMarkingRoomRead = false;
      if (_markRoomReadRequested) {
        _markRoomReadRequested = false;
        unawaited(markActiveRoomRead(reason: 'queued_after:$reason'));
      }
    }
  }

  Future<void> toggleMute() async {
    final member = currentMember;
    final room = activeRoom;
    if (member == null || room == null) {
      return;
    }

    final muted = room.mutedBy[member.id] == true;
    BrowserPushSetupResult? pushSetup;
    var updated = false;
    if (muted) {
      pushSetup = await _syncPushSubscription(force: true);
    }

    await _runBusy(() async {
      await _rpcVoid('app_set_room_mute', <String, dynamic>{
        'p_room_id': room.id,
        'p_member_id': member.id,
        'p_muted': !muted,
      });
      await refreshFamily();
      updated = true;
    });

    if (!updated) {
      return;
    }

    if (muted) {
      if (pushSetup != null &&
          pushSetup.status != BrowserPushSetupStatus.subscribed) {
        pendingPushHelp = pushSetup;
      }
      _setToast(_pushSetupToast(pushSetup));
    } else {
      _setToast('이 채팅방 알림을 껐습니다.');
    }
  }

  Future<void> startOrJoinVoiceCall() async {
    final snapshot = family;
    final member = currentMember;
    final room = activeRoom;
    if (snapshot == null || member == null || room == null) {
      return;
    }

    if (_voiceCallRoomId == room.id &&
        (isVoiceCallConnecting || isVoiceCallJoined)) {
      return;
    }

    if (_voiceCallRoomId != null &&
        _voiceCallRoomId != room.id &&
        (isVoiceCallConnecting || isVoiceCallJoined)) {
      await leaveVoiceCall();
    }

    final startedHere = !room.voiceCallActive;
    var channelName = room.voiceChannelName ?? '';

    try {
      if (startedHere) {
        final payload = await _rpcMap(
          'app_start_room_voice_call',
          <String, dynamic>{'p_room_id': room.id, 'p_member_id': member.id},
        );
        channelName = payload['channelName'] as String? ?? channelName;
        _upsertRoomLocally(
          room.copyWith(
            voiceCallActive: true,
            voiceChannelName: channelName,
            voiceCallStartedAt: DateTime.tryParse(
              payload['startedAt'] as String? ?? '',
            ),
            voiceCallStartedBy: payload['startedBy'] as String?,
          ),
        );
      }
      _isCurrentVoiceCallOutbound = startedHere;
      _hasVoiceCallEverConnected = false;
      unawaited(_syncVoiceCallSoundState());

      if (channelName.isEmpty) {
        throw StateError('Voice channel is not configured.');
      }

      await _joinVoiceCall(
        familyId: snapshot.id,
        roomId: room.id,
        memberId: member.id,
        channelName: channelName,
      );
    } catch (error) {
      _isCurrentVoiceCallOutbound = false;
      unawaited(_syncVoiceCallSoundState());
      voiceCallError = _friendlyError(error, fallback: '음성 통화를 시작하지 못했습니다.');
      notifyListeners();
      _setToast(voiceCallError!);
    }
  }

  Future<void> toggleVoiceMute() async {
    if (_rtcEngine == null || !isVoiceCallJoined) {
      return;
    }

    final muted = !isVoiceCallMuted;
    await _rtcEngine!.muteLocalAudioStream(muted);
    isVoiceCallMuted = muted;
    notifyListeners();
  }

  Future<void> leaveVoiceCall() async {
    final shouldPlayDisconnectTone =
        isVoiceCallJoined || isVoiceCallConnecting || _voiceCallRoomId != null;
    try {
      await _rtcEngine?.leaveChannel();
    } catch (_) {
      // Ignore leave failures.
    }
    _resetVoiceCallState(clearError: false);
    if (shouldPlayDisconnectTone) {
      unawaited(_playVoiceCue(_VoiceCue.disconnect));
    }
    unawaited(_syncVoiceCallSoundState());
    notifyListeners();
  }

  Future<void> endActiveRoomVoiceCall() async {
    final member = currentMember;
    final room = activeRoom;
    if (member == null || room == null) {
      return;
    }

    if (_voiceCallRoomId == room.id &&
        (isVoiceCallJoined || isVoiceCallConnecting)) {
      await leaveVoiceCall();
    }

    await _rpcVoid('app_end_room_voice_call', <String, dynamic>{
      'p_room_id': room.id,
      'p_member_id': member.id,
    });
    _upsertRoomLocally(
      room.copyWith(
        voiceCallActive: false,
        clearVoiceCallStartedAt: true,
        clearVoiceCallStartedBy: true,
      ),
    );
    _setToast('음성 통화를 종료했습니다.');
  }

  Future<void> acceptIncomingVoiceCall() async {
    final room = incomingVoiceCallRoom;
    if (room == null) {
      return;
    }

    final sessionKey = _voiceCallSessionKey(room);
    _dismissedIncomingVoiceCallKey = sessionKey;
    _acceptedVoiceCallOverlayKey = sessionKey;
    _isAcceptingIncomingVoiceCall = true;
    unawaited(_syncVoiceCallSoundState());
    notifyListeners();
    try {
      await selectRoom(room.id);
      await startOrJoinVoiceCall();
    } finally {
      _isAcceptingIncomingVoiceCall = false;
      unawaited(_syncVoiceCallSoundState());
      notifyListeners();
    }
  }

  void dismissIncomingVoiceCallPrompt() {
    final room = incomingVoiceCallRoom;
    if (room == null) {
      return;
    }

    _dismissedIncomingVoiceCallKey = _voiceCallSessionKey(room);
    _acceptedVoiceCallOverlayKey = null;
    unawaited(_syncVoiceCallSoundState());
    notifyListeners();
  }

  Future<void> retryVoiceAudioPlayback() async {
    isVoiceCallAutoplayBlocked = false;
    unawaited(_syncVoiceCallSoundState(forceRestart: true));
    notifyListeners();
  }

  Future<void> startProfileEdit() async {
    final member = currentMember;
    if (member == null) {
      return;
    }
    profileDraftName = member.name;
    profileDraftAvatarKey = member.avatarKey;
    profileDraftAvatarImageDataUrl = member.avatarImageDataUrl;
    notifyListeners();
  }

  void selectPresetAvatar(String? avatarKey) {
    profileDraftAvatarKey = avatarKey;
    profileDraftAvatarImageDataUrl = null;
    notifyListeners();
  }

  Future<void> pickProfileImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) {
      return;
    }
    if ((file.bytes?.length ?? 0) > 1024 * 1024) {
      _setToast('프로필 이미지는 1MB 이하만 허용됩니다.');
      return;
    }
    final bytes = file.bytes;
    if (bytes == null) {
      _setToast('프로필 이미지를 읽지 못했습니다.');
      return;
    }
    final mimeType = file.extension == null
        ? 'image/png'
        : 'image/${file.extension}';
    profileDraftAvatarImageDataUrl = _toDataUrl(bytes, mimeType);
    profileDraftAvatarKey = null;
    notifyListeners();
  }

  Future<void> saveProfile() async {
    final snapshot = family;
    final member = currentMember;
    final draftName = profileDraftName?.trim() ?? '';
    if (snapshot == null || member == null) {
      return;
    }
    if (draftName.isEmpty) {
      _setToast('이름을 입력해 주세요.');
      return;
    }

    await _runBusy(() async {
      final updated =
          await _rpcMap('app_update_member_profile', <String, dynamic>{
            'p_member_id': member.id,
            'p_name': draftName,
            'p_avatar_key': profileDraftAvatarKey ?? '',
            'p_avatar_image_data_url': profileDraftAvatarImageDataUrl ?? '',
          });

      _upsertProfile(
        DeviceProfile(
          familyId: snapshot.id,
          memberId: member.id,
          familyName: snapshot.name,
          memberName: updated['name'] as String? ?? draftName,
          role: updated['role'] as String? ?? member.role,
          avatarKey: updated['avatarKey'] as String?,
          avatarImageDataUrl: updated['avatarImageDataUrl'] as String?,
          savedAt: DateTime.now().toIso8601String(),
        ),
      );

      await refreshFamily();
      _setToast('프로필을 저장했습니다.');
    });
  }

  Future<void> removeMember(MemberRecord target) async {
    final snapshot = family;
    final member = currentMember;
    if (snapshot == null || member == null) {
      return;
    }

    await _runBusy(() async {
      await _rpcVoid('app_remove_member', <String, dynamic>{
        'p_family_id': snapshot.id,
        'p_admin_member_id': member.id,
        'p_target_member_id': target.id,
      });
      savedProfiles.removeWhere(
        (profile) =>
            profile.memberId == target.id && profile.familyId == snapshot.id,
      );
      await _persistLocalState();
      await refreshFamily();
      _setToast('${target.name}님을 탈퇴 처리했습니다.');
    });
  }

  Future<void> touchCurrentMember() async {
    final member = currentMember;
    if (member == null) {
      return;
    }

    try {
      await _rpcVoid('app_touch_member', <String, dynamic>{
        'p_member_id': member.id,
      });
    } catch (_) {
      // Ignore presence failures.
    }
  }

  Future<void> logout() async {
    await _invalidateCurrentSession(removeCurrentProfile: false);
  }

  Future<void> _invalidateCurrentSession({
    required bool removeCurrentProfile,
    String? toast,
  }) async {
    final current = session;
    if (current != null) {
      await _detachPushSubscription(current.memberId);
    }
    if (removeCurrentProfile && current != null) {
      savedProfiles.removeWhere(
        (profile) =>
            profile.familyId == current.familyId &&
            profile.memberId == current.memberId,
      );
    }
    _clearRuntimeState();
    await _persistLocalState();
    if (toast != null && toast.isNotEmpty) {
      toastMessage = toast;
    }
    notifyListeners();
  }

  void _clearRuntimeState() {
    _familyChannel?.unsubscribe();
    _familyChannel = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = null;
    _queuedSends.clear();
    _isDrainingSendQueue = false;
    _isRefreshingFamily = false;
    _refreshRequestedAfterCurrent = false;
    _isMarkingRoomRead = false;
    _markRoomReadRequested = false;
    family = null;
    session = null;
    isBusy = false;
    errorMessage = null;
    pendingImageDataUrl = null;
    pendingImageName = null;
    profileDraftName = null;
    profileDraftAvatarKey = null;
    profileDraftAvatarImageDataUrl = null;
    _dismissedIncomingVoiceCallKey = null;
    _acceptedVoiceCallOverlayKey = null;
    _isAcceptingIncomingVoiceCall = false;
    _isCurrentVoiceCallOutbound = false;
    _hasVoiceCallEverConnected = false;
    _currentVoiceLoopTone = _VoiceLoopTone.none;
    unawaited(_stopVoiceLoopTone());
  }

  void setComposerActive(bool _) {
    // Composition state is tracked in the widget for IME behavior.
  }

  Future<void> _applyRemoteSession(RemoteSessionPayload payload) async {
    session = AppSession(
      familyId: payload.familyId,
      memberId: payload.memberId,
      activeRoomId: payload.activeRoomId,
    );

    _upsertProfile(
      DeviceProfile(
        familyId: payload.familyId,
        memberId: payload.memberId,
        familyName: payload.familyName,
        memberName: payload.memberName,
        role: payload.role,
        avatarKey: payload.avatarKey,
        avatarImageDataUrl: payload.avatarImageDataUrl,
        savedAt: DateTime.now().toIso8601String(),
      ),
    );

    await _persistLocalState();
    notifyListeners();

    await refreshFamily();
    _subscribeFamilyRealtime();
    _startPresenceTimer();
    _startRefreshTimer();
    await touchCurrentMember();
    unawaited(_syncPushSubscription());
  }

  void _subscribeFamilyRealtime() {
    final current = session;
    if (current == null) {
      return;
    }

    _familyChannel?.unsubscribe();
    var channel = _supabase.channel('family-sync:${current.familyId}');
    const tables = <String>[
      'families',
      'members',
      'rooms',
      'room_members',
      'invites',
      'messages',
      'message_reads',
    ];

    for (final table in tables) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: table == 'families'
            ? PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: current.familyId,
              )
            : PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'family_id',
                value: current.familyId,
              ),
        callback: (payload) {
          if (!_applyRealtimePayload(payload)) {
            _scheduleFamilyRefresh(
              reason:
                  'realtime:${payload.table}:${payload.eventType.toString()}',
            );
          }
        },
      );
    }

    _familyChannel = channel;
    channel.subscribe();
  }

  void _startPresenceTimer() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(touchCurrentMember());
    });
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (session != null && !isBusy) {
        _scheduleFamilyRefresh(reason: 'periodic_timer');
      }
    });
  }

  bool _applyRealtimePayload(PostgresChangePayload payload) {
    if (family == null && payload.table != 'members') {
      return false;
    }

    switch (payload.table) {
      case 'members':
        return _applyRealtimeMemberPayload(payload);
      case 'rooms':
        return _applyRealtimeRoomPayload(payload);
      case 'messages':
        return _applyRealtimeMessagePayload(payload);
      case 'message_reads':
        return _applyRealtimeReadPayload(payload);
      default:
        return false;
    }
  }

  bool _applyRealtimeMemberPayload(PostgresChangePayload payload) {
    final current = session;
    if (current == null) {
      return false;
    }

    if (payload.eventType != PostgresChangeEvent.delete) {
      final member = _memberFromRealtimeRecord(
        payload.newRecord,
        fallbackTimestamp: payload.commitTimestamp,
      );
      if (member == null) {
        return false;
      }
      final changed = _upsertRealtimeMember(member);
      if (changed) {
        _logChatTrace(
          'realtime_member_applied',
          details: <String, Object?>{
            'memberId': member.id,
            'eventType': payload.eventType.toString(),
          },
        );
      }
      return changed;
    }

    final memberId = payload.oldRecord['id']?.toString();
    if (memberId != current.memberId) {
      return false;
    }

    unawaited(
      _invalidateCurrentSession(
        removeCurrentProfile: true,
        toast: '가족에서 탈퇴되어 처음 화면으로 이동했습니다. 채팅과 구성원 정보는 초기화되었습니다.',
      ),
    );
    return true;
  }

  bool _applyRealtimeRoomPayload(PostgresChangePayload payload) {
    if (payload.eventType == PostgresChangeEvent.delete) {
      return false;
    }

    final room = _roomFromRealtimeRecord(
      payload.newRecord,
      fallbackTimestamp: payload.commitTimestamp,
    );
    if (room == null) {
      return false;
    }

    final changed = _upsertRoomLocally(room);
    if (changed) {
      _logChatTrace(
        'realtime_room_applied',
        roomId: room.id,
        details: <String, Object?>{
          'eventType': payload.eventType.toString(),
          'voiceCallActive': room.voiceCallActive,
        },
      );
      if (!room.voiceCallActive &&
          _voiceCallRoomId == room.id &&
          (isVoiceCallJoined || isVoiceCallConnecting)) {
        unawaited(leaveVoiceCall());
      }
      unawaited(_syncVoiceCallSoundState());
    }
    return changed;
  }

  bool _applyRealtimeMessagePayload(PostgresChangePayload payload) {
    if (payload.eventType == PostgresChangeEvent.delete) {
      return false;
    }

    final message = _messageFromRealtimeRecord(
      payload.newRecord,
      fallbackTimestamp: payload.commitTimestamp,
    );
    if (message == null) {
      return false;
    }

    final changed = _upsertRealtimeMessage(message);
    if (changed) {
      _logChatTrace(
        'realtime_message_applied',
        messageId: message.id,
        roomId: message.roomId,
        details: <String, Object?>{
          'eventType': payload.eventType.toString(),
          'senderId': message.senderId,
        },
      );
    }
    final member = currentMember;
    final room = activeRoom;
    if (changed &&
        member != null &&
        room != null &&
        room.id == message.roomId &&
        message.senderId != null &&
        message.senderId != member.id) {
      unawaited(markActiveRoomRead());
    }
    return changed;
  }

  bool _applyRealtimeReadPayload(PostgresChangePayload payload) {
    if (payload.eventType == PostgresChangeEvent.delete) {
      return false;
    }

    final record = payload.newRecord;
    final messageId = record['message_id']?.toString();
    final memberId = record['member_id']?.toString();
    if (messageId == null || memberId == null) {
      return false;
    }

    final readAt =
        record['read_at']?.toString() ??
        payload.commitTimestamp.toIso8601String();
    final changed = _applyMessageReadLocally(messageId, memberId, readAt);
    if (changed) {
      _logChatTrace(
        'realtime_read_applied',
        messageId: messageId,
        details: <String, Object?>{'readerId': memberId},
      );
    }
    return changed;
  }

  Future<void> _joinVoiceCall({
    required String familyId,
    required String roomId,
    required String memberId,
    required String channelName,
  }) async {
    isVoiceCallConnecting = true;
    isVoiceCallAutoplayBlocked = false;
    voiceCallError = null;
    _voiceCallRoomId = roomId;
    _voiceCallChannelName = channelName;
    _voiceCallRemoteUids.clear();
    notifyListeners();

    try {
      final tokenPayload = await _fetchVoiceCallToken(
        familyId: familyId,
        roomId: roomId,
        memberId: memberId,
        channelName: channelName,
        uid: _voiceCallUid,
      );
      await _ensureRtcEngine(tokenPayload.appId);
      _voiceCallAppId = tokenPayload.appId;
      _voiceCallUid = tokenPayload.uid;
      await _rtcEngine!.joinChannel(
        token: tokenPayload.token,
        channelId: channelName,
        uid: tokenPayload.uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          autoSubscribeAudio: true,
          autoSubscribeVideo: false,
          publishMicrophoneTrack: true,
          publishCameraTrack: false,
        ),
      );
    } catch (error) {
      _resetVoiceCallState(clearError: true);
      voiceCallError = _friendlyError(error, fallback: '음성 통화에 연결하지 못했습니다.');
      rethrow;
    }
  }

  Future<_VoiceCallTokenPayload> _fetchVoiceCallToken({
    required String familyId,
    required String roomId,
    required String memberId,
    required String channelName,
    int? uid,
  }) async {
    final response = await _supabase.functions.invoke(
      'agora-token',
      body: <String, dynamic>{
        'familyId': familyId,
        'roomId': roomId,
        'memberId': memberId,
        'channelName': channelName,
        'uid': uid,
        'ttlSeconds': 3600,
      },
    );
    final payload = Map<String, dynamic>.from(response.data as Map);
    return _VoiceCallTokenPayload(
      appId: payload['appId'] as String? ?? '',
      token: payload['token'] as String? ?? '',
      uid: (payload['uid'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> _ensureRtcEngine(String appId) async {
    if (_rtcEngine != null && _voiceCallAppId == appId) {
      return;
    }

    await _rtcEngine?.release();
    final engine = createAgoraRtcEngine();
    await engine.initialize(
      RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );
    await _preferNativeCallEarpiece(engine);
    engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          isVoiceCallConnecting = false;
          isVoiceCallJoined = true;
          isVoiceCallMuted = false;
          voiceCallError = null;
          unawaited(_preferNativeCallEarpiece(engine));
          _logChatTrace(
            'voice_join_success',
            roomId: _voiceCallRoomId,
            details: <String, Object?>{
              'uid': connection.localUid,
              'elapsedMs': elapsed,
            },
          );
          unawaited(_syncVoiceCallSoundState());
          notifyListeners();
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          _logChatTrace(
            'voice_leave_channel',
            roomId: _voiceCallRoomId,
            details: <String, Object?>{'duration': stats.duration},
          );
          unawaited(_syncVoiceCallSoundState());
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          final hadRemoteParticipants = _voiceCallRemoteUids.isNotEmpty;
          _voiceCallRemoteUids.add(remoteUid);
          _hasVoiceCallEverConnected = true;
          if (!hadRemoteParticipants) {
            unawaited(_playVoiceCue(_VoiceCue.connected));
          }
          unawaited(_syncVoiceCallSoundState());
          notifyListeners();
        },
        onUserOffline:
            (
              RtcConnection connection,
              int remoteUid,
              UserOfflineReasonType reason,
            ) {
              _voiceCallRemoteUids.remove(remoteUid);
              unawaited(_syncVoiceCallSoundState());
              notifyListeners();
            },
        onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
          unawaited(_renewVoiceCallToken(reason: 'will_expire'));
        },
        onRequestToken: (RtcConnection connection) {
          unawaited(_renewVoiceCallToken(reason: 'request_token'));
        },
        onError: (ErrorCodeType err, String msg) {
          final lower = msg.toLowerCase();
          if (lower.contains('autoplay')) {
            isVoiceCallAutoplayBlocked = true;
          }
          if (lower.contains('permission') || lower.contains('notallowed')) {
            voiceCallError = '마이크 권한이 거부되었습니다.';
          }
          _logChatTrace(
            'voice_error',
            roomId: _voiceCallRoomId,
            details: <String, Object?>{'code': err.toString(), 'message': msg},
          );
          unawaited(_syncVoiceCallSoundState());
          notifyListeners();
        },
      ),
    );
    await engine.enableAudio();
    await engine.disableVideo();
    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    _rtcEngine = engine;
  }

  Future<void> _preferNativeCallEarpiece(RtcEngine engine) async {
    if (kIsWeb) {
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      await engine.setDefaultAudioRouteToSpeakerphone(false);
      await engine.setEnableSpeakerphone(false);
    } catch (_) {
      // Ignore native audio route changes on unsupported platforms.
    }
  }

  Future<void> _renewVoiceCallToken({required String reason}) async {
    final snapshot = family;
    final member = currentMember;
    final roomId = _voiceCallRoomId;
    final channelName = _voiceCallChannelName;
    final uid = _voiceCallUid;
    if (snapshot == null ||
        member == null ||
        roomId == null ||
        channelName == null ||
        uid == null ||
        _rtcEngine == null) {
      return;
    }

    try {
      final tokenPayload = await _fetchVoiceCallToken(
        familyId: snapshot.id,
        roomId: roomId,
        memberId: member.id,
        channelName: channelName,
        uid: uid,
      );
      await _rtcEngine!.renewToken(tokenPayload.token);
      _logChatTrace(
        'voice_token_renewed',
        roomId: roomId,
        details: <String, Object?>{'reason': reason},
      );
    } catch (error) {
      _logChatTrace(
        'voice_token_renew_failed',
        roomId: roomId,
        details: <String, Object?>{'reason': reason, 'error': error.toString()},
      );
    }
  }

  Future<void> _syncVoiceCallSoundState({bool forceRestart = false}) async {
    final desiredTone = _desiredVoiceLoopTone();
    if (!forceRestart && desiredTone == _currentVoiceLoopTone) {
      return;
    }

    _currentVoiceLoopTone = desiredTone;
    if (desiredTone == _VoiceLoopTone.none) {
      await _stopVoiceLoopTone();
      return;
    }

    await _playVoiceLoopTone(desiredTone);
  }

  _VoiceLoopTone _desiredVoiceLoopTone() {
    if (incomingVoiceCallRoom != null) {
      return _VoiceLoopTone.incoming;
    }
    final isAwaitingAnswer =
        _isCurrentVoiceCallOutbound &&
        !_hasVoiceCallEverConnected &&
        _voiceCallRoomId != null &&
        (isVoiceCallConnecting || isVoiceCallJoined) &&
        _voiceCallRemoteUids.isEmpty;
    return isAwaitingAnswer ? _VoiceLoopTone.outgoing : _VoiceLoopTone.none;
  }

  Future<void> _ensureVoiceTonePlayers() async {
    _voiceLoopPlayer ??= AudioPlayer();
    _voiceCuePlayer ??= AudioPlayer();
  }

  Future<void> _playVoiceLoopTone(_VoiceLoopTone tone) async {
    await _ensureVoiceTonePlayers();
    final player = _voiceLoopPlayer!;
    final wavBytes = switch (tone) {
      _VoiceLoopTone.incoming => _buildIncomingVoiceToneWav(),
      _VoiceLoopTone.outgoing => _buildOutgoingVoiceToneWav(),
      _VoiceLoopTone.none => Uint8List(0),
    };
    if (wavBytes.isEmpty) {
      await _stopVoiceLoopTone();
      return;
    }
    try {
      await player.setLoopMode(LoopMode.one);
      await player.setAudioSource(MemoryAudioSource(wavBytes));
      await player.play();
      isVoiceCallAutoplayBlocked = false;
    } catch (_) {
      isVoiceCallAutoplayBlocked = true;
      notifyListeners();
    }
  }

  Future<void> _stopVoiceLoopTone() async {
    final player = _voiceLoopPlayer;
    if (player == null) {
      return;
    }
    try {
      await player.stop();
    } catch (_) {
      // Ignore tone stop failures.
    }
  }

  Future<void> _playVoiceCue(_VoiceCue cue) async {
    await _ensureVoiceTonePlayers();
    final player = _voiceCuePlayer!;
    final wavBytes = switch (cue) {
      _VoiceCue.connected => _buildConnectedVoiceToneWav(),
      _VoiceCue.disconnect => _buildDisconnectedVoiceToneWav(),
    };
    try {
      await player.stop();
      await player.setLoopMode(LoopMode.off);
      await player.setAudioSource(MemoryAudioSource(wavBytes));
      await player.play();
      isVoiceCallAutoplayBlocked = false;
    } catch (_) {
      isVoiceCallAutoplayBlocked = true;
      notifyListeners();
    }
  }

  Uint8List _buildIncomingVoiceToneWav() {
    return synthesizeToneSequenceWav(const <ToneStep>[
      ToneStep(880, 280, volume: 0.26),
      ToneStep(null, 80),
      ToneStep(1046.5, 280, volume: 0.24),
      ToneStep(null, 520),
    ]);
  }

  Uint8List _buildOutgoingVoiceToneWav() {
    return synthesizeToneSequenceWav(const <ToneStep>[
      ToneStep(440, 380, volume: 0.24),
      ToneStep(null, 180),
      ToneStep(440, 380, volume: 0.24),
      ToneStep(null, 780),
    ]);
  }

  Uint8List _buildConnectedVoiceToneWav() {
    return synthesizeToneSequenceWav(const <ToneStep>[
      ToneStep(659.3, 120, volume: 0.24),
      ToneStep(null, 40),
      ToneStep(880, 180, volume: 0.26),
    ]);
  }

  Uint8List _buildDisconnectedVoiceToneWav() {
    return synthesizeToneSequenceWav(const <ToneStep>[
      ToneStep(784, 110, volume: 0.22),
      ToneStep(null, 40),
      ToneStep(523.3, 180, volume: 0.24),
    ]);
  }

  void _resetVoiceCallState({required bool clearError}) {
    isVoiceCallConnecting = false;
    isVoiceCallJoined = false;
    isVoiceCallMuted = false;
    isVoiceCallAutoplayBlocked = false;
    _isCurrentVoiceCallOutbound = false;
    _hasVoiceCallEverConnected = false;
    _voiceCallRoomId = null;
    _voiceCallChannelName = null;
    _voiceCallUid = null;
    _voiceCallRemoteUids.clear();
    if (clearError) {
      voiceCallError = null;
    }
  }

  Future<void> _runBusy(Future<void> Function() operation) async {
    try {
      isBusy = true;
      errorMessage = null;
      notifyListeners();
      await operation();
    } catch (error) {
      errorMessage = _friendlyError(error, fallback: '작업을 완료하지 못했습니다.');
      _setToast(errorMessage!);
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _rpcMap(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    final response = await _supabase.rpc(functionName, params: params);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> _rpcVoid(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    await _supabase.rpc(functionName, params: params);
  }

  void _hydrateLocalState() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return;
    }

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      savedProfiles =
          (json['deviceProfiles'] as List<dynamic>? ?? const <dynamic>[])
              .map(
                (item) => DeviceProfile.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList();
      final sessionJson = json['session'];
      if (sessionJson is Map) {
        session = AppSession.fromJson(Map<String, dynamic>.from(sessionJson));
      }
    } catch (_) {
      savedProfiles = <DeviceProfile>[];
      session = null;
    }
  }

  Future<void> _persistLocalState() async {
    final payload = <String, dynamic>{
      'deviceProfiles': savedProfiles
          .map((profile) => profile.toJson())
          .toList(),
      'session': session?.toJson(),
    };
    await _prefs.setString(_storageKey, jsonEncode(payload));
  }

  void _upsertProfile(DeviceProfile profile) {
    savedProfiles = <DeviceProfile>[
      profile,
      ...savedProfiles.where((item) => item.storageKey != profile.storageKey),
    ];
    unawaited(_persistLocalState());
  }

  void _syncCurrentProfileFromSnapshot() {
    final snapshot = family;
    final member = currentMember;
    if (snapshot == null || member == null) {
      return;
    }

    _upsertProfile(
      DeviceProfile(
        familyId: snapshot.id,
        memberId: member.id,
        familyName: snapshot.name,
        memberName: member.name,
        role: member.role,
        avatarKey: member.avatarKey,
        avatarImageDataUrl: member.avatarImageDataUrl,
        savedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  String? _resolveActiveRoomId(
    FamilySnapshot snapshot,
    String? preferredRoomId,
  ) {
    if (preferredRoomId != null) {
      for (final room in snapshot.rooms) {
        if (room.id == preferredRoomId) {
          return room.id;
        }
      }
    }
    for (final room in snapshot.rooms) {
      if (room.type == 'family') {
        return room.id;
      }
    }
    return snapshot.rooms.isNotEmpty ? snapshot.rooms.first.id : null;
  }

  bool _hasUnreadMessages(
    FamilySnapshot snapshot,
    String roomId,
    String memberId,
  ) {
    for (final message in snapshot.messages) {
      if (message.roomId != roomId || message.senderId == memberId) {
        continue;
      }
      if (!message.readBy.containsKey(memberId)) {
        return true;
      }
    }
    return false;
  }

  List<MessageRecord> _pendingMessagesForSnapshot(FamilySnapshot snapshot) {
    final snapshotMessageIds = snapshot.messages
        .map((message) => message.id)
        .toSet();
    return _queuedSends
        .where(
          (item) =>
              item.familyId == snapshot.id &&
              !snapshotMessageIds.contains(item.optimisticMessage.id),
        )
        .map((item) => item.optimisticMessage)
        .toList();
  }

  Future<BrowserPushSetupResult> _syncPushSubscription({
    bool force = false,
  }) async {
    if (!browserPushSupported) {
      return const BrowserPushSetupResult(
        status: BrowserPushSetupStatus.unsupported,
      );
    }
    if (_isSyncingPushSubscription) {
      return const BrowserPushSetupResult(
        status: BrowserPushSetupStatus.unavailable,
        detail: 'sync_in_progress',
      );
    }

    final current = session;
    final member = currentMember;
    if (current == null || member == null) {
      return const BrowserPushSetupResult(
        status: BrowserPushSetupStatus.unavailable,
        detail: 'missing_session',
      );
    }
    if (!force &&
        _registeredPushMemberId == member.id &&
        _registeredPushEndpoint != null &&
        _registeredPushEndpoint!.isNotEmpty) {
      return BrowserPushSetupResult(
        status: BrowserPushSetupStatus.subscribed,
        subscription: BrowserPushSubscription(
          endpoint: _registeredPushEndpoint!,
          p256dh: '',
          auth: '',
          userAgent: '',
        ),
      );
    }

    _isSyncingPushSubscription = true;
    try {
      final result = await ensureBrowserPushSubscription(
        pushConfigUrl: '$kSupabaseUrl/functions/v1/push-notifications',
        serviceWorkerPath: 'push_service_worker.js',
      );
      final subscription = result.subscription;
      if (subscription == null) {
        return result;
      }

      await _rpcMap('app_upsert_push_subscription', <String, dynamic>{
        'p_member_id': member.id,
        'p_endpoint': subscription.endpoint,
        'p_p256dh': subscription.p256dh,
        'p_auth': subscription.auth,
        'p_user_agent': subscription.userAgent,
      });
      _registeredPushEndpoint = subscription.endpoint;
      _registeredPushMemberId = member.id;
      return BrowserPushSetupResult(
        status: BrowserPushSetupStatus.subscribed,
        subscription: subscription,
      );
    } catch (_) {
      // Keep chat usable even if browser push registration fails.
      return const BrowserPushSetupResult(
        status: BrowserPushSetupStatus.unavailable,
        detail: 'registration_failed',
      );
    } finally {
      _isSyncingPushSubscription = false;
    }
  }

  String _pushSetupToast(BrowserPushSetupResult? result) {
    switch (result?.status) {
      case BrowserPushSetupStatus.subscribed:
        return '이 채팅방 알림을 켰습니다.';
      case BrowserPushSetupStatus.permissionDenied:
        return '이 채팅방 알림은 켰지만 브라우저 알림 권한이 허용되지 않았습니다.';
      case BrowserPushSetupStatus.unsupported:
        return '이 채팅방 알림은 켰지만 현재 환경은 웹 푸시를 지원하지 않습니다.';
      case BrowserPushSetupStatus.unavailable:
      case null:
        return '이 채팅방 알림은 켰지만 브라우저 푸시 등록은 완료되지 않았습니다.';
    }
  }

  Future<void> _detachPushSubscription(String memberId) async {
    if (!browserPushSupported) {
      return;
    }

    try {
      final endpoint = await removeBrowserPushSubscription(
        serviceWorkerPath: 'push_service_worker.js',
      );
      await _rpcVoid('app_remove_push_subscription', <String, dynamic>{
        'p_member_id': memberId,
        'p_endpoint': endpoint ?? _registeredPushEndpoint,
      });
    } catch (_) {
      // Ignore push cleanup failures during logout or invalidation.
    } finally {
      _registeredPushEndpoint = null;
      _registeredPushMemberId = null;
    }
  }

  Future<void> _applyPendingPushNavigationIfReady() async {
    final intent = _pendingPushNavigation;
    final current = session;
    final snapshot = family;
    if (intent == null || current == null || snapshot == null) {
      return;
    }
    if (intent.familyId != current.familyId) {
      return;
    }

    final targetRoom = snapshot.rooms
        .where((room) => room.id == intent.roomId)
        .firstOrNull;
    if (targetRoom == null) {
      _pendingPushNavigation = null;
      clearPendingPushNavigationIntent();
      return;
    }

    if (current.activeRoomId != targetRoom.id) {
      session = current.copyWith(activeRoomId: targetRoom.id);
      await _persistLocalState();
      notifyListeners();
    }
    _pendingPushNavigation = null;
    clearPendingPushNavigationIntent();
    unawaited(markActiveRoomRead());
  }

  void _setToast(String value) {
    toastMessage = value;
    notifyListeners();
  }

  void _startSendQueue() {
    if (_isDrainingSendQueue) {
      return;
    }
    _isDrainingSendQueue = true;
    unawaited(_drainSendQueue());
  }

  Future<void> _drainSendQueue() async {
    while (_queuedSends.isNotEmpty) {
      final queued = _queuedSends.first;
      try {
        await _sendQueuedMessage(queued);
        _queuedSends.removeAt(0);
        _logChatTrace(
          'send_queue_item_completed',
          messageId: queued.optimisticMessage.id,
          roomId: queued.roomId,
          details: <String, Object?>{
            'remainingQueueDepth': _queuedSends.length,
          },
        );
      } catch (error) {
        _queuedSends.removeAt(0);
        if (queued.imageDataUrl != null &&
            pendingImageDataUrl == null &&
            pendingImageName == null) {
          pendingImageDataUrl = queued.imageDataUrl;
          pendingImageName = queued.imageName;
        }
        _removeOptimisticMessage(queued.optimisticMessage.id);
        _logChatTrace(
          'send_queue_item_failed',
          messageId: queued.optimisticMessage.id,
          roomId: queued.roomId,
          details: <String, Object?>{
            'error': error.toString(),
            'remainingQueueDepth': _queuedSends.length,
          },
        );
        errorMessage = _friendlyError(error, fallback: '메시지를 보내지 못했습니다.');
        _setToast(errorMessage!);
      }
    }
    _isDrainingSendQueue = false;
  }

  Future<void> _sendQueuedMessage(_QueuedSend queued) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        _logChatTrace(
          'send_rpc_start',
          messageId: queued.optimisticMessage.id,
          roomId: queued.roomId,
          details: <String, Object?>{
            'attempt': attempt + 1,
            'elapsedSinceClickMs': DateTime.now()
                .difference(queued.initiatedAt)
                .inMilliseconds,
            'elapsedSinceOptimisticMs': DateTime.now()
                .difference(queued.optimisticAppendedAt)
                .inMilliseconds,
          },
        );
        await _rpcMap('app_send_message', <String, dynamic>{
          'p_family_id': queued.familyId,
          'p_room_id': queued.roomId,
          'p_sender_id': queued.senderId,
          'p_message_type': queued.messageType,
          'p_text': queued.text,
          'p_image_data_url': queued.imageDataUrl ?? '',
          'p_audio_data_url': queued.audioDataUrl ?? '',
          'p_audio_duration_ms': queued.audioDurationMs,
          'p_client_message_id': queued.optimisticMessage.id,
        });
        _logChatTrace(
          'send_rpc_response',
          messageId: queued.optimisticMessage.id,
          roomId: queued.roomId,
          details: <String, Object?>{
            'attempt': attempt + 1,
            'elapsedSinceClickMs': DateTime.now()
                .difference(queued.initiatedAt)
                .inMilliseconds,
          },
        );
        return;
      } catch (error) {
        lastError = error;
        _logChatTrace(
          'send_rpc_error',
          messageId: queued.optimisticMessage.id,
          roomId: queued.roomId,
          details: <String, Object?>{
            'attempt': attempt + 1,
            'error': error.toString(),
          },
        );
        if (!_shouldRetryQueuedSend(error) || attempt == 2) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }

    if (lastError != null) {
      throw lastError;
    }
  }

  void _scheduleFamilyRefresh({
    bool immediate = false,
    String reason = 'unspecified',
  }) {
    if (session == null) {
      return;
    }
    if (immediate) {
      _refreshDebounceTimer?.cancel();
      unawaited(refreshFamily(skipErrorToast: true, reason: reason));
      return;
    }
    if (_refreshDebounceTimer?.isActive ?? false) {
      return;
    }
    _refreshDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (session != null && !isBusy) {
        unawaited(refreshFamily(skipErrorToast: true, reason: reason));
      }
    });
  }

  MemberRecord? _memberFromRealtimeRecord(
    Map<String, dynamic> record, {
    required DateTime fallbackTimestamp,
  }) {
    final id = record['id']?.toString();
    final familyId = record['family_id']?.toString();
    if (id == null || familyId == null) {
      return null;
    }

    return MemberRecord(
      id: id,
      familyId: familyId,
      name: record['name']?.toString() ?? '',
      role: record['role']?.toString() ?? 'member',
      createdAt:
          DateTime.tryParse(record['created_at']?.toString() ?? '') ??
          fallbackTimestamp,
      lastSeenAt: DateTime.tryParse(record['last_seen_at']?.toString() ?? ''),
      avatarKey: record['avatar_key']?.toString(),
      avatarImageDataUrl: record['avatar_image_data_url']?.toString(),
    );
  }

  RoomRecord? _roomFromRealtimeRecord(
    Map<String, dynamic> record, {
    required DateTime fallbackTimestamp,
  }) {
    final snapshot = family;
    final id = record['id']?.toString();
    final familyId = record['family_id']?.toString();
    if (snapshot == null || id == null || familyId == null) {
      return null;
    }

    final existing = snapshot.rooms.where((room) => room.id == id).firstOrNull;
    if (existing == null) {
      return null;
    }

    return existing.copyWith(
      familyId: familyId,
      type: record['type']?.toString() ?? existing.type,
      title: record['title']?.toString() ?? existing.title,
      createdAt:
          DateTime.tryParse(record['created_at']?.toString() ?? '') ??
          fallbackTimestamp,
      voiceCallActive: record['voice_call_active'] == true,
      voiceChannelName: record['voice_channel_name']?.toString(),
      voiceCallStartedAt: DateTime.tryParse(
        record['voice_call_started_at']?.toString() ?? '',
      ),
      voiceCallStartedBy: record['voice_call_started_by']?.toString(),
    );
  }

  bool _shouldRetryQueuedSend(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('statement timeout') ||
        text.contains('upstream request') ||
        text.contains('request timeout') ||
        text.contains('gateway timeout') ||
        text.contains('timed out') ||
        text.contains('timeout') ||
        text.contains('cancelled') ||
        text.contains('temporarily unavailable') ||
        text.contains('connection closed') ||
        text.contains('network');
  }

  bool _shouldInvalidateSession(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('member not found') ||
        text.contains('member is not in room') ||
        text.contains('not allowed in this room') ||
        text.contains('탈퇴');
  }

  MessageRecord? _messageFromRealtimeRecord(
    Map<String, dynamic> record, {
    required DateTime fallbackTimestamp,
  }) {
    final id = record['id']?.toString();
    final roomId = record['room_id']?.toString();
    final familyId = record['family_id']?.toString();
    if (id == null || roomId == null || familyId == null) {
      return null;
    }

    final createdAt =
        DateTime.tryParse(record['created_at']?.toString() ?? '') ??
        fallbackTimestamp;
    final senderId = record['sender_id']?.toString();
    final initialReadBy = <String, String>{};
    if (senderId != null && senderId.isNotEmpty) {
      initialReadBy[senderId] = createdAt.toIso8601String();
    }

    return MessageRecord(
      id: id,
      roomId: roomId,
      familyId: familyId,
      senderId: senderId,
      type: record['type']?.toString() ?? 'text',
      text: record['text']?.toString() ?? '',
      imageDataUrl: record['image_data_url']?.toString(),
      audioDataUrl: record['audio_data_url']?.toString(),
      audioDurationMs: (record['audio_duration_ms'] as num?)?.toInt(),
      createdAt: createdAt,
      readBy: initialReadBy,
    );
  }

  bool _upsertRealtimeMessage(MessageRecord message) {
    final snapshot = family;
    if (snapshot == null) {
      return false;
    }

    final updatedMessages = List<MessageRecord>.from(snapshot.messages);
    final index = updatedMessages.indexWhere((item) => item.id == message.id);
    if (index >= 0) {
      final existing = updatedMessages[index];
      final merged = MessageRecord(
        id: message.id,
        roomId: message.roomId,
        familyId: message.familyId,
        senderId: message.senderId,
        type: message.type,
        text: message.text,
        imageDataUrl: message.imageDataUrl,
        audioDataUrl: message.audioDataUrl,
        audioDurationMs: message.audioDurationMs,
        createdAt: message.createdAt,
        readBy: <String, String>{...message.readBy, ...existing.readBy},
      );
      if (_messageEquals(existing, merged)) {
        return false;
      }
      updatedMessages[index] = merged;
    } else {
      final insertIndex = _findMessageInsertIndex(updatedMessages, message);
      updatedMessages.insert(insertIndex, message);
    }
    _replaceFamilyMessages(snapshot, updatedMessages);
    return true;
  }

  bool _applyMessageReadLocally(
    String messageId,
    String memberId,
    String readAt,
  ) {
    final snapshot = family;
    if (snapshot == null) {
      return false;
    }

    var changed = false;
    final updatedMessages = snapshot.messages.map((message) {
      if (message.id != messageId || message.readBy.containsKey(memberId)) {
        return message;
      }
      changed = true;
      return MessageRecord(
        id: message.id,
        roomId: message.roomId,
        familyId: message.familyId,
        senderId: message.senderId,
        type: message.type,
        text: message.text,
        imageDataUrl: message.imageDataUrl,
        audioDataUrl: message.audioDataUrl,
        audioDurationMs: message.audioDurationMs,
        createdAt: message.createdAt,
        readBy: <String, String>{...message.readBy, memberId: readAt},
      );
    }).toList();

    if (!changed) {
      return false;
    }

    _replaceFamilyMessages(snapshot, updatedMessages);
    return true;
  }

  void _markRoomReadLocally(String roomId, String memberId) {
    final snapshot = family;
    if (snapshot == null) {
      return;
    }

    final readAt = DateTime.now().toIso8601String();
    var changed = false;
    final updatedMessages = snapshot.messages.map((message) {
      if (message.roomId != roomId ||
          message.senderId == memberId ||
          message.readBy.containsKey(memberId)) {
        return message;
      }
      changed = true;
      return MessageRecord(
        id: message.id,
        roomId: message.roomId,
        familyId: message.familyId,
        senderId: message.senderId,
        type: message.type,
        text: message.text,
        imageDataUrl: message.imageDataUrl,
        audioDataUrl: message.audioDataUrl,
        audioDurationMs: message.audioDurationMs,
        createdAt: message.createdAt,
        readBy: <String, String>{...message.readBy, memberId: readAt},
      );
    }).toList();

    if (!changed) {
      return;
    }

    _replaceFamilyMessages(snapshot, updatedMessages);
  }

  bool _upsertRealtimeMember(MemberRecord member) {
    final snapshot = family;
    if (snapshot == null) {
      return false;
    }

    final updatedMembers = List<MemberRecord>.from(snapshot.members);
    final index = updatedMembers.indexWhere((item) => item.id == member.id);
    if (index >= 0) {
      final existing = updatedMembers[index];
      if (_memberEquals(existing, member)) {
        return false;
      }
      updatedMembers[index] = member;
    } else {
      updatedMembers.add(member);
      updatedMembers.sort(
        (left, right) => left.createdAt.compareTo(right.createdAt),
      );
    }

    _replaceFamilyMembers(snapshot, updatedMembers);
    return true;
  }

  bool _upsertRoomLocally(RoomRecord room) {
    final snapshot = family;
    if (snapshot == null) {
      return false;
    }

    final updatedRooms = List<RoomRecord>.from(snapshot.rooms);
    final index = updatedRooms.indexWhere((item) => item.id == room.id);
    if (index < 0) {
      return false;
    }

    final existing = updatedRooms[index];
    if (_roomEquals(existing, room)) {
      return false;
    }

    updatedRooms[index] = room;
    _replaceFamilyRooms(snapshot, updatedRooms);
    return true;
  }

  String? _voiceCallSessionKey(RoomRecord? room) {
    if (room == null || !room.voiceCallActive) {
      return null;
    }
    final startedAt = room.voiceCallStartedAt?.toIso8601String() ?? '';
    final channelName = room.voiceChannelName ?? '';
    return '${room.id}|$channelName|$startedAt';
  }

  void _syncVoiceCallOverlayState() {
    final snapshot = family;
    if (snapshot == null) {
      _dismissedIncomingVoiceCallKey = null;
      _acceptedVoiceCallOverlayKey = null;
      return;
    }

    final activeSessionKeys = snapshot.rooms
        .where((room) => room.voiceCallActive)
        .map(_voiceCallSessionKey)
        .whereType<String>()
        .toSet();

    if (_dismissedIncomingVoiceCallKey != null &&
        !activeSessionKeys.contains(_dismissedIncomingVoiceCallKey)) {
      _dismissedIncomingVoiceCallKey = null;
    }
    if (_acceptedVoiceCallOverlayKey != null &&
        !activeSessionKeys.contains(_acceptedVoiceCallOverlayKey)) {
      _acceptedVoiceCallOverlayKey = null;
    }
  }

  void _replaceFamilyRooms(FamilySnapshot snapshot, List<RoomRecord> rooms) {
    family = FamilySnapshot(
      id: snapshot.id,
      name: snapshot.name,
      createdAt: snapshot.createdAt,
      members: snapshot.members,
      rooms: rooms,
      invites: snapshot.invites,
      messages: snapshot.messages,
      settings: snapshot.settings,
    );
    _syncVoiceCallOverlayState();
    unawaited(_syncVoiceCallSoundState());
    notifyListeners();
  }

  void _replaceFamilyMembers(
    FamilySnapshot snapshot,
    List<MemberRecord> members,
  ) {
    family = FamilySnapshot(
      id: snapshot.id,
      name: snapshot.name,
      createdAt: snapshot.createdAt,
      members: members,
      rooms: snapshot.rooms,
      invites: snapshot.invites,
      messages: snapshot.messages,
      settings: snapshot.settings,
    );
    notifyListeners();
  }

  void _replaceFamilyMessages(
    FamilySnapshot snapshot,
    List<MessageRecord> messages,
  ) {
    family = FamilySnapshot(
      id: snapshot.id,
      name: snapshot.name,
      createdAt: snapshot.createdAt,
      members: snapshot.members,
      rooms: snapshot.rooms,
      invites: snapshot.invites,
      messages: messages,
      settings: snapshot.settings,
    );
    notifyListeners();
  }

  void _appendOptimisticMessage(MessageRecord message) {
    final snapshot = family;
    if (snapshot == null) {
      return;
    }

    family = FamilySnapshot(
      id: snapshot.id,
      name: snapshot.name,
      createdAt: snapshot.createdAt,
      members: snapshot.members,
      rooms: snapshot.rooms,
      invites: snapshot.invites,
      messages: <MessageRecord>[...snapshot.messages, message],
      settings: snapshot.settings,
    );
    notifyListeners();
  }

  void _removeOptimisticMessage(String messageId) {
    final snapshot = family;
    if (snapshot == null) {
      return;
    }

    family = FamilySnapshot(
      id: snapshot.id,
      name: snapshot.name,
      createdAt: snapshot.createdAt,
      members: snapshot.members,
      rooms: snapshot.rooms,
      invites: snapshot.invites,
      messages: snapshot.messages
          .where((message) => message.id != messageId)
          .toList(),
      settings: snapshot.settings,
    );
    notifyListeners();
  }

  int _findMessageInsertIndex(
    List<MessageRecord> messages,
    MessageRecord incoming,
  ) {
    if (messages.isEmpty) {
      return 0;
    }
    if (!incoming.createdAt.isBefore(messages.last.createdAt)) {
      return messages.length;
    }
    for (var index = messages.length - 1; index >= 0; index--) {
      if (!incoming.createdAt.isBefore(messages[index].createdAt)) {
        return index + 1;
      }
    }
    return 0;
  }

  bool _memberEquals(MemberRecord left, MemberRecord right) {
    return left.id == right.id &&
        left.familyId == right.familyId &&
        left.name == right.name &&
        left.role == right.role &&
        left.createdAt == right.createdAt &&
        left.lastSeenAt == right.lastSeenAt &&
        left.avatarKey == right.avatarKey &&
        left.avatarImageDataUrl == right.avatarImageDataUrl;
  }

  bool _roomEquals(RoomRecord left, RoomRecord right) {
    return left.id == right.id &&
        left.familyId == right.familyId &&
        left.type == right.type &&
        left.title == right.title &&
        left.createdAt == right.createdAt &&
        listEquals(left.memberIds, right.memberIds) &&
        mapEquals(left.mutedBy, right.mutedBy) &&
        left.voiceCallActive == right.voiceCallActive &&
        left.voiceChannelName == right.voiceChannelName &&
        left.voiceCallStartedAt == right.voiceCallStartedAt &&
        left.voiceCallStartedBy == right.voiceCallStartedBy;
  }

  bool _messageEquals(MessageRecord left, MessageRecord right) {
    return left.id == right.id &&
        left.roomId == right.roomId &&
        left.familyId == right.familyId &&
        left.senderId == right.senderId &&
        left.type == right.type &&
        left.text == right.text &&
        left.imageDataUrl == right.imageDataUrl &&
        left.audioDataUrl == right.audioDataUrl &&
        left.audioDurationMs == right.audioDurationMs &&
        left.createdAt == right.createdAt &&
        mapEquals(left.readBy, right.readBy);
  }

  void _logChatTrace(
    String event, {
    String? messageId,
    String? roomId,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    if (!kDebugMode) {
      return;
    }

    final payload = <String, Object?>{
      'event': event,
      'messageId': messageId,
      'roomId': roomId,
      'timestamp': DateTime.now().toIso8601String(),
      ...details,
    };
    debugPrint('[chat-trace] ${jsonEncode(payload)}');
  }

  String _friendlyError(Object error, {required String fallback}) {
    final text = error.toString();
    if (_shouldRetryQueuedSend(error)) {
      return '서버 응답이 지연되고 있습니다. 잠시 후 다시 시도해 주세요.';
    }
    if (text.contains('message:')) {
      final match = RegExp(r'message: ([^,}]+)').firstMatch(text);
      if (match != null) {
        return match.group(1)!.trim();
      }
    }
    return text.isEmpty ? fallback : text;
  }

  String _toDataUrl(Uint8List bytes, String mimeType) {
    final encoded = base64Encode(bytes);
    return 'data:$mimeType;base64,$encoded';
  }

  @override
  void dispose() {
    _familyChannel?.unsubscribe();
    _presenceTimer?.cancel();
    _refreshTimer?.cancel();
    _refreshDebounceTimer?.cancel();
    unawaited(_voiceLoopPlayer?.dispose() ?? Future<void>.value());
    unawaited(_voiceCuePlayer?.dispose() ?? Future<void>.value());
    unawaited(_rtcEngine?.release() ?? Future<void>.value());
    super.dispose();
  }
}

class _QueuedSend {
  const _QueuedSend({
    required this.familyId,
    required this.roomId,
    required this.senderId,
    required this.messageType,
    required this.text,
    required this.imageDataUrl,
    required this.audioDataUrl,
    required this.audioDurationMs,
    required this.imageName,
    required this.optimisticMessage,
    required this.initiatedAt,
    required this.optimisticAppendedAt,
  });

  final String familyId;
  final String roomId;
  final String senderId;
  final String messageType;
  final String text;
  final String? imageDataUrl;
  final String? audioDataUrl;
  final int? audioDurationMs;
  final String? imageName;
  final MessageRecord optimisticMessage;
  final DateTime initiatedAt;
  final DateTime optimisticAppendedAt;
}

class _VoiceCallTokenPayload {
  const _VoiceCallTokenPayload({
    required this.appId,
    required this.token,
    required this.uid,
  });

  final String appId;
  final String token;
  final int uid;
}

enum _VoiceLoopTone { none, incoming, outgoing }

enum _VoiceCue { connected, disconnect }
