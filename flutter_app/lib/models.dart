class AppSession {
  const AppSession({
    required this.familyId,
    required this.memberId,
    required this.activeRoomId,
  });

  final String familyId;
  final String memberId;
  final String? activeRoomId;

  AppSession copyWith({
    String? familyId,
    String? memberId,
    String? activeRoomId,
    bool clearActiveRoom = false,
  }) {
    return AppSession(
      familyId: familyId ?? this.familyId,
      memberId: memberId ?? this.memberId,
      activeRoomId: clearActiveRoom ? null : activeRoomId ?? this.activeRoomId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'familyId': familyId,
      'memberId': memberId,
      'activeRoomId': activeRoomId,
    };
  }

  factory AppSession.fromJson(Map<String, dynamic> json) {
    return AppSession(
      familyId: json['familyId'] as String,
      memberId: json['memberId'] as String,
      activeRoomId: json['activeRoomId'] as String?,
    );
  }
}

class DeviceProfile {
  const DeviceProfile({
    required this.familyId,
    required this.memberId,
    required this.familyName,
    required this.memberName,
    required this.role,
    this.avatarKey,
    this.avatarImageDataUrl,
    required this.savedAt,
  });

  final String familyId;
  final String memberId;
  final String familyName;
  final String memberName;
  final String role;
  final String? avatarKey;
  final String? avatarImageDataUrl;
  final String savedAt;

  String get storageKey => '$familyId:$memberId';

  Map<String, dynamic> toJson() {
    return {
      'familyId': familyId,
      'memberId': memberId,
      'familyName': familyName,
      'memberName': memberName,
      'role': role,
      'avatarKey': avatarKey,
      'avatarImageDataUrl': avatarImageDataUrl,
      'savedAt': savedAt,
    };
  }

  factory DeviceProfile.fromJson(Map<String, dynamic> json) {
    return DeviceProfile(
      familyId: json['familyId'] as String,
      memberId: json['memberId'] as String,
      familyName: json['familyName'] as String? ?? '가족',
      memberName: json['memberName'] as String? ?? '사용자',
      role: json['role'] as String? ?? 'member',
      avatarKey: json['avatarKey'] as String?,
      avatarImageDataUrl: json['avatarImageDataUrl'] as String?,
      savedAt: json['savedAt'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
}

class FamilySettings {
  const FamilySettings({
    required this.allowGroupRooms,
  });

  final bool allowGroupRooms;

  factory FamilySettings.fromJson(Map<String, dynamic>? json) {
    return FamilySettings(
      allowGroupRooms: json?['allowGroupRooms'] == true,
    );
  }
}

class FamilySnapshot {
  const FamilySnapshot({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.members,
    required this.rooms,
    required this.invites,
    required this.messages,
    required this.settings,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final List<MemberRecord> members;
  final List<RoomRecord> rooms;
  final List<InviteRecord> invites;
  final List<MessageRecord> messages;
  final FamilySettings settings;

  factory FamilySnapshot.fromJson(Map<String, dynamic> json) {
    return FamilySnapshot(
      id: json['id'] as String,
      name: json['name'] as String? ?? '가족',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      members: ((json['members'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => MemberRecord.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList())
          .cast<MemberRecord>(),
      rooms: ((json['rooms'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => RoomRecord.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList())
          .cast<RoomRecord>(),
      invites: ((json['invites'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => InviteRecord.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList())
          .cast<InviteRecord>(),
      messages: ((json['messages'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => MessageRecord.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList())
          .cast<MessageRecord>(),
      settings: FamilySettings.fromJson(json['settings'] as Map<String, dynamic>?),
    );
  }
}

class MemberRecord {
  const MemberRecord({
    required this.id,
    required this.familyId,
    required this.name,
    required this.role,
    required this.createdAt,
    required this.lastSeenAt,
    this.avatarKey,
    this.avatarImageDataUrl,
  });

  final String id;
  final String familyId;
  final String name;
  final String role;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
  final String? avatarKey;
  final String? avatarImageDataUrl;

  factory MemberRecord.fromJson(Map<String, dynamic> json) {
    return MemberRecord(
      id: json['id'] as String,
      familyId: json['familyId'] as String,
      name: json['name'] as String? ?? '사용자',
      role: json['role'] as String? ?? 'member',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? ''),
      avatarKey: json['avatarKey'] as String?,
      avatarImageDataUrl: json['avatarImageDataUrl'] as String?,
    );
  }
}

class RoomRecord {
  const RoomRecord({
    required this.id,
    required this.familyId,
    required this.type,
    required this.title,
    required this.createdAt,
    required this.memberIds,
    required this.mutedBy,
  });

  final String id;
  final String familyId;
  final String type;
  final String title;
  final DateTime createdAt;
  final List<String> memberIds;
  final Map<String, bool> mutedBy;

  factory RoomRecord.fromJson(Map<String, dynamic> json) {
    return RoomRecord(
      id: json['id'] as String,
      familyId: json['familyId'] as String,
      type: json['type'] as String? ?? 'family',
      title: json['title'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      memberIds: (json['memberIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      mutedBy: ((json['mutedBy'] as Map?) ?? const {})
          .map((key, value) => MapEntry(key.toString(), value == true)),
    );
  }
}

class InviteRecord {
  const InviteRecord({
    required this.id,
    required this.familyId,
    required this.code,
    required this.createdBy,
    required this.status,
    this.usedBy,
    this.usedAt,
    required this.createdAt,
  });

  final String id;
  final String familyId;
  final String code;
  final String createdBy;
  final String status;
  final String? usedBy;
  final DateTime? usedAt;
  final DateTime createdAt;

  factory InviteRecord.fromJson(Map<String, dynamic> json) {
    return InviteRecord(
      id: json['id'] as String,
      familyId: json['familyId'] as String,
      code: json['code'] as String,
      createdBy: json['createdBy'] as String,
      status: json['status'] as String? ?? 'active',
      usedBy: json['usedBy'] as String?,
      usedAt: DateTime.tryParse(json['usedAt'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class MessageRecord {
  const MessageRecord({
    required this.id,
    required this.roomId,
    required this.familyId,
    required this.senderId,
    required this.type,
    required this.text,
    this.imageDataUrl,
    required this.createdAt,
    required this.readBy,
  });

  final String id;
  final String roomId;
  final String familyId;
  final String? senderId;
  final String type;
  final String text;
  final String? imageDataUrl;
  final DateTime createdAt;
  final Map<String, String> readBy;

  factory MessageRecord.fromJson(Map<String, dynamic> json) {
    return MessageRecord(
      id: json['id'] as String,
      roomId: json['roomId'] as String,
      familyId: json['familyId'] as String,
      senderId: json['senderId'] as String?,
      type: json['type'] as String? ?? 'text',
      text: json['text'] as String? ?? '',
      imageDataUrl: json['imageDataUrl'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      readBy: ((json['readBy'] as Map?) ?? const {})
          .map((key, value) => MapEntry(key.toString(), value.toString())),
    );
  }
}

class RemoteSessionPayload {
  const RemoteSessionPayload({
    required this.familyId,
    required this.memberId,
    required this.activeRoomId,
    required this.familyName,
    required this.memberName,
    required this.role,
    this.avatarKey,
    this.avatarImageDataUrl,
  });

  final String familyId;
  final String memberId;
  final String? activeRoomId;
  final String familyName;
  final String memberName;
  final String role;
  final String? avatarKey;
  final String? avatarImageDataUrl;

  factory RemoteSessionPayload.fromJson(Map<String, dynamic> json) {
    return RemoteSessionPayload(
      familyId: json['familyId'] as String,
      memberId: json['memberId'] as String,
      activeRoomId: json['activeRoomId'] as String?,
      familyName: json['familyName'] as String? ?? '가족',
      memberName: json['memberName'] as String? ?? '사용자',
      role: json['role'] as String? ?? 'member',
      avatarKey: json['avatarKey'] as String?,
      avatarImageDataUrl: json['avatarImageDataUrl'] as String?,
    );
  }
}
