import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../app_version.dart';
import '../models.dart';
import '../ui/design_tokens.dart';
import 'common.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.appState, this.onClose});

  final FamilyChatAppState appState;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final family = appState.family;
    final member = appState.currentMember;
    if (family == null || member == null) {
      return const SizedBox.shrink();
    }

    return StitchedPanel(
      color: AppColors.creamSoft.withValues(alpha: 0.96),
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          _HeroHeader(familyName: family.name, onClose: onClose),
          const SizedBox(height: 16),
          StitchedPanel(
            color: AppColors.paper,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AvatarBadge(
                      name: member.name,
                      avatarKey: member.avatarKey,
                      avatarImageDataUrl: member.avatarImageDataUrl,
                      size: 62,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          CuteTag(
                            label: member.role == 'admin' ? '관리자' : '구성원',
                            icon: member.role == 'admin'
                                ? Icons.verified_rounded
                                : Icons.favorite_rounded,
                            color: member.role == 'admin'
                                ? AppColors.sky
                                : AppColors.pink,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            member.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            presenceText(member.lastSeenAt),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await appState.startProfileEdit();
                        if (context.mounted) {
                          await showProfileDialog(context, appState);
                        }
                      },
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('프로필 수정'),
                    ),
                    OutlinedButton.icon(
                      onPressed: appState.logout,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('로그아웃'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: '채팅방',
            tint: AppColors.paper,
            icon: Icons.chat_bubble_rounded,
            child: Column(
              children: family.rooms.map((room) {
                final selected = appState.activeRoom?.id == room.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SidebarTile(
                    tint: selected ? AppColors.lavender : AppColors.creamSoft,
                    selected: selected,
                    leading: room.type == 'family'
                        ? Icons.groups_rounded
                        : Icons.forum_rounded,
                    title: roomTitle(room, family, member.id, family.members),
                    subtitle: room.type == 'family' ? '가족 전체방' : '1:1 대화',
                    onTap: () async {
                      await appState.selectRoom(room.id);
                      onClose?.call();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: '가족 구성원',
            tint: const Color(0xFFFFF7F8),
            icon: Icons.favorite_rounded,
            child: Column(
              children: family.members
                  .map(
                    (target) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _memberTile(context, family, member, target),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (appState.isAdmin) ...<Widget>[
            const SizedBox(height: 16),
            SectionCard(
              title: '초대 코드',
              tint: AppColors.sky.withValues(alpha: 0.42),
              icon: Icons.key_rounded,
              action: FilledButton.tonalIcon(
                onPressed: appState.createInvite,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('코드 생성'),
              ),
              child: Column(
                children: family.invites.map((invite) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SidebarTile(
                      tint: AppColors.paper,
                      leading: Icons.mark_email_unread_rounded,
                      title: invite.code,
                      subtitle:
                          '${invite.status} · ${DateFormat('M.d HH:mm').format(invite.createdAt.toLocal())}',
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SectionCard(
            title: '이 기기 프로필',
            tint: AppColors.butter.withValues(alpha: 0.36),
            icon: Icons.devices_rounded,
            child: Column(
              children: appState.savedProfiles.map((profile) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    onTap: () async {
                      await appState.activateSavedProfile(profile);
                      onClose?.call();
                    },
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.paper,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Row(
                        children: <Widget>[
                          AvatarBadge(
                            name: profile.memberName,
                            avatarKey: profile.avatarKey,
                            avatarImageDataUrl: profile.avatarImageDataUrl,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  profile.memberName,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  profile.familyName,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberTile(
    BuildContext context,
    FamilySnapshot family,
    MemberRecord current,
    MemberRecord target,
  ) {
    final removable =
        appState.isAdmin && target.role != 'admin' && target.id != current.id;

    return Ink(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: target.id == current.id
            ? AppColors.mint.withValues(alpha: 0.7)
            : AppColors.paper,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: <Widget>[
          AvatarBadge(
            name: target.name,
            avatarKey: target.avatarKey,
            avatarImageDataUrl: target.avatarImageDataUrl,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  target.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${target.role == 'admin' ? '관리자' : '구성원'} · ${presenceText(target.lastSeenAt)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (target.id != current.id)
            IconButton.filledTonal(
              tooltip: '대화',
              onPressed: () async {
                await appState.openDirectMessage(target);
                onClose?.call();
              },
              icon: const Icon(Icons.forum_rounded),
            ),
          if (target.id != current.id) ...<Widget>[
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '전화',
              onPressed: () async {
                await appState.startDirectVoiceCall(target);
                onClose?.call();
              },
              style: IconButton.styleFrom(
                backgroundColor: AppColors.sky,
                foregroundColor: AppColors.plum,
              ),
              icon: const Icon(Icons.call_rounded),
            ),
          ],
          if (removable)
            IconButton(
              tooltip: '탈퇴 처리',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('구성원 탈퇴'),
                    content: Text('${target.name}님을 가족에서 탈퇴 처리할까요?'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('취소'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('확인'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await appState.removeMember(target);
                }
              },
              icon: const Icon(Icons.person_remove_alt_1_rounded),
            ),
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.familyName, this.onClose});

  final String familyName;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return StitchedPanel(
      color: const Color(0xFFFFF0F7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const <Widget>[
                    CuteTag(
                      label: 'Family Space',
                      icon: Icons.auto_awesome_rounded,
                      color: AppColors.pink,
                    ),
                    CuteTag(
                      label: kAppVersion,
                      icon: Icons.favorite_rounded,
                      color: AppColors.sky,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  familyName,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '따뜻하고 포근한 우리 가족 채팅 공간',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (onClose != null)
            IconButton.filledTonal(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.tint = AppColors.paper,
    this.selected = false,
  });

  final IconData leading;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color tint;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: selected
              ? Border.all(
                  color: AppColors.lavenderDeep.withValues(alpha: 0.34),
                  width: 1.4,
                )
              : null,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.paper.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              alignment: Alignment.center,
              child: Icon(leading, color: AppColors.plum),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.arrow_forward_ios_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}
