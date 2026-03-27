import 'package:flutter/material.dart';

import '../app_state.dart';
import '../platform/web_push_types.dart';
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

Future<void> showPushPermissionHelpDialog(
  BuildContext context,
  BrowserPushSetupResult result,
) async {
  final platform = Theme.of(context).platform;
  final isApple = platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  final title = switch (result.status) {
    BrowserPushSetupStatus.permissionDenied => '알림 권한이 차단되어 있습니다',
    BrowserPushSetupStatus.unsupported => '현재 브라우저는 웹 푸시를 지원하지 않습니다',
    BrowserPushSetupStatus.unavailable => '브라우저 푸시 등록이 완료되지 않았습니다',
    BrowserPushSetupStatus.subscribed => '알림이 연결되었습니다',
  };

  await showDialog<void>(
    context: context,
    builder: (context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: StitchedPanel(
          padding: const EdgeInsets.all(22),
          color: AppColors.creamSoft,
          child: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  Text(
                    isApple
                        ? '아이폰은 Safari로 연 뒤 홈 화면에 추가한 웹앱에서만 알림이 동작할 수 있습니다.'
                        : '안드로이드는 일반 Chrome 또는 Edge에서 열고 사이트 알림 권한을 허용해야 합니다.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  _HelpBlock(
                    title: '안드로이드 Chrome',
                    steps: const <String>[
                      'Chrome에서 사이트를 직접 엽니다.',
                      '주소창 왼쪽 아이콘 -> 권한 또는 사이트 설정 -> 알림 -> 허용',
                      'Chrome 우측 상단 점 3개 -> 설정 -> 사이트 설정 -> 알림 -> 알림 허용',
                      '휴대폰 설정 -> 앱 -> Chrome -> 알림 -> 허용',
                    ],
                  ),
                  const SizedBox(height: 12),
                  _HelpBlock(
                    title: '아이폰 Safari',
                    steps: const <String>[
                      'Safari에서 사이트를 엽니다.',
                      '공유 버튼 -> 홈 화면에 추가 -> 추가',
                      '홈 화면에 생성된 아이콘으로 다시 실행합니다.',
                      '아이폰 설정 -> 알림 -> 해당 웹앱 이름 -> 알림 허용',
                    ],
                  ),
                  const SizedBox(height: 12),
                  _HelpBlock(
                    title: '데스크톱 Chrome',
                    steps: const <String>[
                      'Chrome 우측 상단 점 3개 -> 설정',
                      '개인정보 및 보안 -> 사이트 설정 -> 알림',
                      '알림을 허용으로 바꾸고, 차단 목록에 사이트가 있으면 제거',
                      '사이트 접속 후 주소창 왼쪽 아이콘 -> 사이트 설정 -> 알림 -> 허용',
                    ],
                  ),
                  if ((result.detail ?? '').isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    Text(
                      '진단 정보: ${result.detail}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('확인'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _HelpBlock extends StatelessWidget {
  const _HelpBlock({required this.title, required this.steps});

  final String title;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lavender.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++) ...<Widget>[
            Text('${i + 1}. ${steps[i]}', style: Theme.of(context).textTheme.bodyMedium),
            if (i != steps.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}
