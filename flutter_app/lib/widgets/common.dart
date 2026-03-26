import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/design_tokens.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.action,
    this.tint,
    this.icon,
  });

  final String title;
  final Widget child;
  final Widget? action;
  final Color? tint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StitchedPanel(
      color: tint ?? AppColors.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.paper.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: AppColors.plum),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
                ),
              ),
              if (action case final Widget action) action,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
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
    final borderRadius = BorderRadius.circular(size / 2);
    if (avatarImageDataUrl != null && avatarImageDataUrl!.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[AppColors.pink, AppColors.lavender],
          ),
          borderRadius: borderRadius,
          boxShadow: AppShadows.floating,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Image.network(avatarImageDataUrl!, fit: BoxFit.cover),
        ),
      );
    }

    final background = avatarColor(name);
    final label = avatarKey == null
        ? name.characters.first.toUpperCase()
        : avatarGlyph(avatarKey!);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            background,
            Color.lerp(background, Colors.white, 0.28)!,
          ],
        ),
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.paper, width: 2.4),
        boxShadow: AppShadows.floating,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.paper,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.34,
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
  final partnerId = room.memberIds
      .where((id) => id != currentMemberId)
      .firstOrNull;
  final partner = members.where((member) => member.id == partnerId).firstOrNull;
  return partner?.name ?? '1:1 채팅';
}

String presenceText(DateTime? lastSeenAt) {
  if (lastSeenAt == null) {
    return '최근 접속 정보 없음';
  }
  final diff = DateTime.now().difference(lastSeenAt.toLocal());
  if (diff.inMinutes < 1) {
    return '지금 활동 중';
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
    AppColors.pinkDeep,
    AppColors.lavenderDeep,
    Color(0xFF8AB6F9),
    Color(0xFFF8B97D),
    Color(0xFF8FD2B2),
    Color(0xFFF49AB8),
  ];
  final sum = value.runes.fold<int>(0, (prev, rune) => prev + rune);
  return palette[sum % palette.length];
}

Future<void> showProfileDialog(
  BuildContext context,
  FamilyChatAppState appState,
) async {
  final controller = TextEditingController(
    text: appState.profileDraftName ?? '',
  );
  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: StitchedPanel(
              padding: const EdgeInsets.all(22),
              color: AppColors.creamSoft,
              child: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: const <Widget>[
                          CuteTag(
                            label: '프로필',
                            icon: Icons.favorite_rounded,
                            color: AppColors.pink,
                          ),
                          SizedBox(width: 8),
                          CuteTag(
                            label: '꾸미기',
                            icon: Icons.auto_awesome_rounded,
                            color: AppColors.sky,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '프로필 꾸미기',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '이름과 아바타를 부드럽고 귀엽게 정리해 보세요.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: AvatarBadge(
                          name: controller.text.isEmpty
                              ? '사용자'
                              : controller.text,
                          avatarKey: appState.profileDraftAvatarKey,
                          avatarImageDataUrl:
                              appState.profileDraftAvatarImageDataUrl,
                          size: 84,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: controller,
                        onChanged: (value) {
                          appState.profileDraftName = value;
                          setDialogState(() {});
                        },
                        decoration: const InputDecoration(
                          labelText: '이름',
                          prefixIcon: Icon(Icons.edit_rounded),
                        ),
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
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              await appState.pickProfileImage();
                              setDialogState(() {});
                            },
                            icon: const Icon(Icons.image_rounded),
                            label: const Text('이미지 업로드'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              appState.selectPresetAvatar(null);
                              setDialogState(() {});
                            },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('기본으로 돌리기'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('닫기'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () async {
                              appState.profileDraftName = controller.text;
                              await appState.saveProfile();
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            icon: const Icon(Icons.favorite_rounded),
                            label: const Text('저장'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
  controller.dispose();
}
