import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'platform/web_push.dart';

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
  String? _registeredPushEndpoint;
  String? _registeredPushMemberId;
  PushNavigationIntent? _pendingPushNavigation = getPendingPushNavigationIntent();

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

  void clearToast() {
    toastMessage = null;
    notifyListeners();
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

  Future<void> refreshFamily({bool skipErrorToast = false}) async {
    final current = session;
    if (current == null) {
      return;
    }
    if (_isRefreshingFamily) {
      _refreshRequestedAfterCurrent = true;
      return;
    }

    _refreshDebounceTimer?.cancel();
    _isRefreshingFamily = true;
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
      _isRefreshingFamily = false;
      if (_refreshRequestedAfterCurrent) {
        _refreshRequestedAfterCurrent = false;
        _scheduleFamilyRefresh(immediate: true);
      }
    }
  }

  Future<void> selectRoom(String roomId) async {
    final current = session;
    if (current == null) {
      return;
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

  Future<bool> sendMessage(String rawText) async {
    final snapshot = family;
    final member = currentMember;
    final room = activeRoom;
    if (snapshot == null || member == null || room == null) {
      return false;
    }

    final text = rawText.trim();
    final image = pendingImageDataUrl;
    final imageName = pendingImageName;
    if (text.isEmpty && (image == null || image.isEmpty)) {
      _setToast('메시지나 이미지를 입력해 주세요.');
      return false;
    }

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
      createdAt: DateTime.now(),
      readBy: <String, String>{member.id: DateTime.now().toIso8601String()},
    );

    pendingImageDataUrl = null;
    pendingImageName = null;
    _appendOptimisticMessage(optimisticMessage);

    _queuedSends.add(
      _QueuedSend(
        familyId: snapshot.id,
        roomId: room.id,
        senderId: member.id,
        messageType: image != null ? 'image' : 'text',
        text: text,
        imageDataUrl: image,
        imageName: imageName,
        optimisticMessage: optimisticMessage,
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

  Future<void> markActiveRoomRead() async {
    final snapshot = family;
    final member = currentMember;
    final room = activeRoom;
    if (snapshot == null || member == null || room == null) {
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
      await _rpcVoid('app_mark_room_read', <String, dynamic>{
        'p_room_id': room.id,
        'p_member_id': member.id,
      });
    } catch (_) {
      // Ignore read marker failures.
    } finally {
      _isMarkingRoomRead = false;
      if (_markRoomReadRequested) {
        _markRoomReadRequested = false;
        unawaited(markActiveRoomRead());
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
      _setToast(_pushSetupToast(pushSetup));
    } else {
      _setToast('이 채팅방 알림을 껐습니다.');
    }
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
            _scheduleFamilyRefresh();
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
        _scheduleFamilyRefresh();
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
      case 'messages':
        return _applyRealtimeMessagePayload(payload);
      case 'message_reads':
        return _applyRealtimeReadPayload(payload);
      default:
        return false;
    }
  }

  bool _applyRealtimeMemberPayload(PostgresChangePayload payload) {
    if (payload.eventType != PostgresChangeEvent.delete) {
      return false;
    }

    final current = session;
    if (current == null) {
      return false;
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
    return _applyMessageReadLocally(messageId, memberId, readAt);
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
        if (_queuedSends.isEmpty) {
          unawaited(touchCurrentMember());
        }
      } catch (error) {
        _queuedSends.removeAt(0);
        if (queued.imageDataUrl != null &&
            pendingImageDataUrl == null &&
            pendingImageName == null) {
          pendingImageDataUrl = queued.imageDataUrl;
          pendingImageName = queued.imageName;
        }
        _removeOptimisticMessage(queued.optimisticMessage.id);
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
        await _rpcMap('app_send_message', <String, dynamic>{
          'p_family_id': queued.familyId,
          'p_room_id': queued.roomId,
          'p_sender_id': queued.senderId,
          'p_message_type': queued.messageType,
          'p_text': queued.text,
          'p_image_data_url': queued.imageDataUrl ?? '',
          'p_client_message_id': queued.optimisticMessage.id,
        });
        return;
      } catch (error) {
        lastError = error;
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

  void _scheduleFamilyRefresh({bool immediate = false}) {
    if (session == null) {
      return;
    }
    if (immediate) {
      _refreshDebounceTimer?.cancel();
      unawaited(refreshFamily(skipErrorToast: true));
      return;
    }
    if (_refreshDebounceTimer?.isActive ?? false) {
      return;
    }
    _refreshDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (session != null && !isBusy) {
        unawaited(refreshFamily(skipErrorToast: true));
      }
    });
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
      updatedMessages[index] = MessageRecord(
        id: message.id,
        roomId: message.roomId,
        familyId: message.familyId,
        senderId: message.senderId,
        type: message.type,
        text: message.text,
        imageDataUrl: message.imageDataUrl,
        createdAt: message.createdAt,
        readBy: <String, String>{...message.readBy, ...existing.readBy},
      );
    } else {
      updatedMessages.add(message);
    }

    updatedMessages.sort(
      (left, right) => left.createdAt.compareTo(right.createdAt),
    );
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
        createdAt: message.createdAt,
        readBy: <String, String>{...message.readBy, memberId: readAt},
      );
    }).toList();

    if (!changed) {
      return;
    }

    _replaceFamilyMessages(snapshot, updatedMessages);
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
    required this.imageName,
    required this.optimisticMessage,
  });

  final String familyId;
  final String roomId;
  final String senderId;
  final String messageType;
  final String text;
  final String? imageDataUrl;
  final String? imageName;
  final MessageRecord optimisticMessage;
}
