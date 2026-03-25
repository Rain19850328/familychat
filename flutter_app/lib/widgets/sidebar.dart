import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.appState,
    this.onClose,
  });

  final FamilyChatAppState appState;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final family = appState.family;
    final member = appState.currentMember;
    if (family == null || member == null) {
      return const SizedBox.shrink();
    }

    return ColoredBox(
      color: const Color(0xFFF3EFE6),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Family Space', style: TextStyle(color: Color(0xFF4A746C), fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(family.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                if (onClose != null) IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AvatarBadge(name: member.name, avatarKey: member.avatarKey, avatarImageDataUrl: member.avatarImageDataUrl, size: 54),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(member.role == 'admin' ? '관리자' : '구성원', style: const TextStyle(color: Color(0xFF4A746C), fontWeight: FontWeight.w700)),
                              Text(member.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                              Text(presenceText(member.lastSeenAt), style: const TextStyle(color: Colors.black54)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: () async {
                            await appState.startProfileEdit();
                            if (context.mounted) {
                              await showProfileDialog(context, appState);
                            }
                          },
                          child: const Text('프로필 수정'),
                        ),
                        OutlinedButton(
                          onPressed: appState.logout,
                          child: const Text('로그아웃'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SectionCard(
              title: '채팅방',
              child: Column(
                children: family.rooms.map((room) {
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    selected: appState.activeRoom?.id == room.id,
                    selectedTileColor: const Color(0xFFE0F1E8),
                    leading: Icon(room.type == 'family' ? Icons.groups_rounded : Icons.chat_bubble_rounded),
                    title: Text(roomTitle(room, family, member.id, family.members)),
                    subtitle: Text(room.type == 'family' ? '가족 전체방' : '1:1 채팅'),
                    onTap: () async {
                      await appState.selectRoom(room.id);
                      onClose?.call();
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '가족 구성원',
              child: Column(
                children: family.members.map((target) => _memberTile(context, family, member, target)).toList(),
              ),
            ),
            if (appState.isAdmin) ...[
              const SizedBox(height: 16),
              SectionCard(
                title: '초대 코드',
                action: FilledButton.tonal(
                  onPressed: appState.createInvite,
                  child: const Text('코드 생성'),
                ),
                child: Column(
                  children: family.invites.map((invite) {
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      title: SelectableText(invite.code),
                      subtitle: Text('${invite.status} · ${DateFormat('M.d HH:mm').format(invite.createdAt.toLocal())}'),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SectionCard(
              title: '이 기기 프로필',
              child: Column(
                children: appState.savedProfiles.map((profile) {
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    leading: AvatarBadge(
                      name: profile.memberName,
                      avatarKey: profile.avatarKey,
                      avatarImageDataUrl: profile.avatarImageDataUrl,
                    ),
                    title: Text(profile.memberName),
                    subtitle: Text(profile.familyName),
                    onTap: () async {
                      await appState.activateSavedProfile(profile);
                      onClose?.call();
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(BuildContext context, FamilySnapshot family, MemberRecord current, MemberRecord target) {
    final removable = appState.isAdmin && target.role != 'admin' && target.id != current.id;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      leading: AvatarBadge(
        name: target.name,
        avatarKey: target.avatarKey,
        avatarImageDataUrl: target.avatarImageDataUrl,
      ),
      title: Text(target.name),
      subtitle: Text('${target.role == 'admin' ? '관리자' : '구성원'} · ${presenceText(target.lastSeenAt)}'),
      trailing: Wrap(
        spacing: 6,
        children: [
          if (target.id != current.id)
            IconButton(
              tooltip: 'DM',
              onPressed: () async {
                await appState.openDirectMessage(target);
                onClose?.call();
              },
              icon: const Icon(Icons.forum_rounded),
            ),
          if (removable)
            IconButton(
              tooltip: '탈퇴 처리',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('구성원 탈퇴'),
                    content: Text('${target.name}님을 가족에서 탈퇴 처리할까요?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('확인')),
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
