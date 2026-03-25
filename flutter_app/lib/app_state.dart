import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

const String kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://csarhidurfxdmcworbtk.supabase.co',
);
const String kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNzYXJoaWR1cmZ4ZG1jd29yYnRrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4MTIwNTgsImV4cCI6MjA4OTM4ODA1OH0.AW7mIgO0M_qk3xjrLkATrHO__HWFozcTyxjEIf-rjr8',
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

  String pendingMessage = '';
  String? pendingImageDataUrl;
  String? pendingImageName;
  String? profileDraftName;
  String? profileDraftAvatarKey;
  String? profileDraftAvatarImageDataUrl;

  RealtimeChannel? _familyChannel;
  Timer? _presenceTimer;

  Future<void> bootstrap() async {
    _hydrateLocalState();
    isBootstrapping = false;
    notifyListeners();

    if (session != null) {
      await refreshFamily(skipErrorToast: true);
      _subscribeFamilyRealtime();
      _startPresenceTimer();
      unawaited(touchCurrentMember());
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
    return snapshot.messages.where((message) => message.roomId == room.id).toList();
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
    unawaited(touchCurrentMember());
  }

  Future<void> refreshFamily({bool skipErrorToast = false}) async {
    final current = session;
    if (current == null) {
      return;
    }

    try {
      final payload = await _rpcMap('app_get_family_snapshot', <String, dynamic>{
        'p_family_id': current.familyId,
      });
      final snapshot = FamilySnapshot.fromJson(payload);
      final resolvedRoom = _resolveActiveRoomId(snapshot, current.activeRoomId);
      family = snapshot;
      session = current.copyWith(activeRoomId: resolvedRoom);
      _syncCurrentProfileFromSnapshot();
      await _persistLocalState();
      notifyListeners();
    } catch (error) {
      if (!skipErrorToast) {
        _setToast(_friendlyError(error, fallback: '가족 정보를 불러오지 못했습니다.'));
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
      final payload = await _rpcMap('app_get_or_create_dm_room', <String, dynamic>{
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

  Future<void> sendMessage() async {
    final snapshot = family;
    final member = currentMember;
    final room = activeRoom;
    if (snapshot == null || member == null || room == null) {
      return;
    }

    final text = pendingMessage.trim();
    final image = pendingImageDataUrl;
    if (text.isEmpty && (image == null || image.isEmpty)) {
      _setToast('메시지나 이미지를 입력하세요.');
      return;
    }

    await _runBusy(() async {
      await _rpcMap('app_send_message', <String, dynamic>{
        'p_family_id': snapshot.id,
        'p_room_id': room.id,
        'p_sender_id': member.id,
        'p_message_type': image != null ? 'image' : 'text',
        'p_text': text,
        'p_image_data_url': image ?? '',
      });
      pendingMessage = '';
      pendingImageDataUrl = null;
      pendingImageName = null;
      notifyListeners();
      await touchCurrentMember();
      await refreshFamily();
      await markActiveRoomRead();
    });
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
    final mimeType = file.extension == null ? 'image/png' : 'image/${file.extension}';
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
    final member = currentMember;
    final room = activeRoom;
    if (member == null || room == null) {
      return;
    }

    try {
      await _rpcVoid('app_mark_room_read', <String, dynamic>{
        'p_room_id': room.id,
        'p_member_id': member.id,
      });
    } catch (_) {}
  }

  Future<void> toggleMute() async {
    final member = currentMember;
    final room = activeRoom;
    if (member == null || room == null) {
      return;
    }

    await _runBusy(() async {
      final muted = room.mutedBy[member.id] == true;
      await _rpcVoid('app_set_room_mute', <String, dynamic>{
        'p_room_id': room.id,
        'p_member_id': member.id,
        'p_muted': !muted,
      });
      await refreshFamily();
    });
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
    final mimeType = file.extension == null ? 'image/png' : 'image/${file.extension}';
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
      _setToast('이름을 입력하세요.');
      return;
    }

    await _runBusy(() async {
      final updated = await _rpcMap('app_update_member_profile', <String, dynamic>{
        'p_member_id': member.id,
        'p_name': draftName,
        'p_avatar_key': profileDraftAvatarKey ?? '',
        'p_avatar_image_data_url': profileDraftAvatarImageDataUrl ?? '',
      });

      _upsertProfile(DeviceProfile(
        familyId: snapshot.id,
        memberId: member.id,
        familyName: snapshot.name,
        memberName: updated['name'] as String? ?? draftName,
        role: updated['role'] as String? ?? member.role,
        avatarKey: updated['avatarKey'] as String?,
        avatarImageDataUrl: updated['avatarImageDataUrl'] as String?,
        savedAt: DateTime.now().toIso8601String(),
      ));

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
      savedProfiles.removeWhere((profile) => profile.memberId == target.id && profile.familyId == snapshot.id);
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
    } catch (_) {}
  }

  Future<void> logout() async {
    _familyChannel?.unsubscribe();
    _familyChannel = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    family = null;
    session = null;
    pendingMessage = '';
    pendingImageDataUrl = null;
    pendingImageName = null;
    await _persistLocalState();
    notifyListeners();
  }

  Future<void> _applyRemoteSession(RemoteSessionPayload payload) async {
    session = AppSession(
      familyId: payload.familyId,
      memberId: payload.memberId,
      activeRoomId: payload.activeRoomId,
    );

    _upsertProfile(DeviceProfile(
      familyId: payload.familyId,
      memberId: payload.memberId,
      familyName: payload.familyName,
      memberName: payload.memberName,
      role: payload.role,
      avatarKey: payload.avatarKey,
      avatarImageDataUrl: payload.avatarImageDataUrl,
      savedAt: DateTime.now().toIso8601String(),
    ));

    await refreshFamily();
    _subscribeFamilyRealtime();
    _startPresenceTimer();
    await touchCurrentMember();
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
        callback: (_) {
          unawaited(refreshFamily(skipErrorToast: true));
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

  Future<Map<String, dynamic>> _rpcMap(String functionName, Map<String, dynamic> params) async {
    final response = await _supabase.rpc(functionName, params: params);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> _rpcVoid(String functionName, Map<String, dynamic> params) async {
    await _supabase.rpc(functionName, params: params);
  }

  void _hydrateLocalState() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return;
    }

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      savedProfiles = (json['deviceProfiles'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => DeviceProfile.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      final sessionJson = json['session'] as Map<String, dynamic>?;
      if (sessionJson != null) {
        session = AppSession.fromJson(sessionJson);
      }
    } catch (_) {
      savedProfiles = <DeviceProfile>[];
      session = null;
    }
  }

  Future<void> _persistLocalState() async {
    final payload = <String, dynamic>{
      'deviceProfiles': savedProfiles.map((profile) => profile.toJson()).toList(),
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

    _upsertProfile(DeviceProfile(
      familyId: snapshot.id,
      memberId: member.id,
      familyName: snapshot.name,
      memberName: member.name,
      role: member.role,
      avatarKey: member.avatarKey,
      avatarImageDataUrl: member.avatarImageDataUrl,
      savedAt: DateTime.now().toIso8601String(),
    ));
  }

  String? _resolveActiveRoomId(FamilySnapshot snapshot, String? preferredRoomId) {
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

  void _setToast(String value) {
    toastMessage = value;
    notifyListeners();
  }

  String _friendlyError(Object error, {required String fallback}) {
    final text = error.toString();
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
    super.dispose();
  }
}
