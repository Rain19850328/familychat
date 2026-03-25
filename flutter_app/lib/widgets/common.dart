import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (action case final Widget action) action,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class AvatarBadge extends StatelessWidget {
  const AvatarBadge({
    super.key,
    required this.name,
    required this.avatarKey,
    required this.avatarImageDataUrl,
    this.size = 44,
  });

  final String name;
  final String? avatarKey;
  final String? avatarImageDataUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (avatarImageDataUrl != null && avatarImageDataUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.network(
          avatarImageDataUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    final background = avatarColor(name);
    final label = avatarKey == null ? name.characters.first.toUpperCase() : avatarGlyph(avatarKey!);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

String roomTitle(
  RoomRecord room,
  FamilySnapshot family,
  String currentMemberId,
  List<MemberRecord> members,
) {
  if (room.type == 'family') {
    return room.title.isEmpty ? '우리 가족방' : room.title;
  }
  final partnerId = room.memberIds.where((id) => id != currentMemberId).firstOrNull;
  final partner = members.where((member) => member.id == partnerId).firstOrNull;
  return partner?.name ?? '1:1 채팅';
}

String presenceText(DateTime? lastSeenAt) {
  if (lastSeenAt == null) {
    return '최근 접속 정보 없음';
  }
  final diff = DateTime.now().difference(lastSeenAt.toLocal());
  if (diff.inMinutes < 1) {
    return '현재 활동 중';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}분 전 활동';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours}시간 전 접속';
  }
  return '${diff.inDays}일 전 접속';
}

String avatarGlyph(String key) {
  switch (key) {
    case 'adult-man':
      return 'M';
    case 'adult-woman':
      return 'W';
    case 'boy':
      return 'B';
    case 'girl':
      return 'G';
    case 'sparkle-friend':
      return '*';
    default:
      return '?';
  }
}

String avatarLabel(String key) {
  switch (key) {
    case 'adult-man':
      return '어른 남자';
    case 'adult-woman':
      return '어른 여자';
    case 'boy':
      return '아이 남자';
    case 'girl':
      return '아이 여자';
    case 'sparkle-friend':
      return '반짝 친구';
    default:
      return key;
  }
}

Color avatarColor(String value) {
  const palette = <Color>[
    Color(0xFFF36B4F),
    Color(0xFF217974),
    Color(0xFF4F7CFF),
    Color(0xFFFF9E3D),
    Color(0xFF7A5CFF),
    Color(0xFFFF6F91),
  ];
  final sum = value.runes.fold<int>(0, (prev, rune) => prev + rune);
  return palette[sum % palette.length];
}

Future<void> showProfileDialog(BuildContext context, FamilyChatAppState appState) async {
  final controller = TextEditingController(text: appState.profileDraftName ?? '');
  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('프로필 수정'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: AvatarBadge(
                        name: controller.text.isEmpty ? '사용자' : controller.text,
                        avatarKey: appState.profileDraftAvatarKey,
                        avatarImageDataUrl: appState.profileDraftAvatarImageDataUrl,
                        size: 76,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      onChanged: (value) {
                        appState.profileDraftName = value;
                        setDialogState(() {});
                      },
                      decoration: const InputDecoration(labelText: '이름'),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: presetAvatarKeys.map((key) {
                        return ChoiceChip(
                          label: Text(avatarLabel(key)),
                          selected: key == appState.profileDraftAvatarKey,
                          onSelected: (_) {
                            appState.selectPresetAvatar(key);
                            setDialogState(() {});
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: () async {
                            await appState.pickProfileImage();
                            setDialogState(() {});
                          },
                          child: const Text('이미지 업로드'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            appState.selectPresetAvatar(null);
                            setDialogState(() {});
                          },
                          child: const Text('기본으로 되돌리기'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
              FilledButton(
                onPressed: () async {
                  appState.profileDraftName = controller.text;
                  await appState.saveProfile();
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('저장'),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
}
