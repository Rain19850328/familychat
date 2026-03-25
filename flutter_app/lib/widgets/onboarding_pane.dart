import 'package:flutter/material.dart';

import '../app_state.dart';
import 'common.dart';

class OnboardingPane extends StatelessWidget {
  const OnboardingPane({
    super.key,
    required this.appState,
    required this.familyNameController,
    required this.adminNameController,
    required this.inviteCodeController,
    required this.memberNameController,
  });

  final FamilyChatAppState appState;
  final TextEditingController familyNameController;
  final TextEditingController adminNameController;
  final TextEditingController inviteCodeController;
  final TextEditingController memberNameController;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100 ? 3 : width >= 760 ? 2 : 1;
    final panels = <Widget>[
      _panel(
        title: '저장된 프로필',
        subtitle: 'This Device',
        expandChild: columns > 1,
        child: appState.savedProfiles.isEmpty
            ? const Text('이 기기에 저장된 프로필이 없습니다.')
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: appState.savedProfiles.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final profile = appState.savedProfiles[index];
                  return ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    tileColor: const Color(0xFFF7F8F6),
                    leading: AvatarBadge(
                      name: profile.memberName,
                      avatarKey: profile.avatarKey,
                      avatarImageDataUrl: profile.avatarImageDataUrl,
                    ),
                    title: Text(profile.memberName),
                    subtitle: Text('${profile.familyName} · ${profile.role == 'admin' ? '관리자' : '구성원'}'),
                    trailing: FilledButton(
                      onPressed: () => appState.activateSavedProfile(profile),
                      child: const Text('열기'),
                    ),
                  );
                },
              ),
      ),
      _panel(
        title: '가족 만들기',
        subtitle: 'Admin Only',
        expandChild: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: familyNameController,
              decoration: const InputDecoration(labelText: '가족 이름'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: adminNameController,
              decoration: const InputDecoration(labelText: '관리자 이름'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => appState.createFamily(
                  familyName: familyNameController.text,
                  adminName: adminNameController.text,
                ),
                child: const Text('가족 그룹 생성'),
              ),
            ),
          ],
        ),
      ),
      _panel(
        title: '초대로 참여하기',
        subtitle: 'Invite Only',
        expandChild: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: inviteCodeController,
              decoration: const InputDecoration(labelText: '초대 코드'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: memberNameController,
              decoration: const InputDecoration(labelText: '이름'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => appState.joinFamily(
                  inviteCode: inviteCodeController.text,
                  memberName: memberNameController.text,
                ),
                child: const Text('가족 그룹 입장'),
              ),
            ),
          ],
        ),
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7F3EA), Color(0xFFE7F4EE), Color(0xFFFFF7E8)],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E4036),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Closed Family Chat',
                        style: TextStyle(color: Color(0xFFB7F1D7), fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '가족끼리만 연결되는 채팅',
                        style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Flutter Web으로 재구성된 가족 전용 채팅입니다. 관리자 초대 코드 기반으로만 입장할 수 있고, 가족 전체방과 DM만 운영됩니다.',
                        style: TextStyle(color: Color(0xFFDDEFE6), fontSize: 16, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (columns == 1)
                  Column(
                    children: [
                      for (var index = 0; index < panels.length; index++) ...[
                        panels[index],
                        if (index != panels.length - 1) const SizedBox(height: 20),
                      ],
                    ],
                  )
                else
                  GridView.count(
                    crossAxisCount: columns,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.05,
                    children: panels,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel({
    required String title,
    required String subtitle,
    required Widget child,
    required bool expandChild,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: const TextStyle(color: Color(0xFF4A746C), fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            if (expandChild) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}
