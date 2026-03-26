import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ui/design_tokens.dart';
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
    final columns = width >= 1160
        ? 3
        : width >= 760
        ? 2
        : 1;
    final panels = <Widget>[
      _panel(
        context,
        tint: AppColors.sky.withValues(alpha: 0.42),
        title: '이 기기에 저장된 프로필',
        subtitle: 'This Device',
        icon: Icons.devices_rounded,
        expandChild: columns > 1,
        child: appState.savedProfiles.isEmpty
            ? _emptySavedProfiles(context)
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: appState.savedProfiles.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final profile = appState.savedProfiles[index];
                  return Ink(
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
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${profile.familyName} · ${profile.role == 'admin' ? '관리자' : '구성원'}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: () =>
                              appState.activateSavedProfile(profile),
                          child: const Text('열기'),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      _panel(
        context,
        tint: AppColors.pink.withValues(alpha: 0.42),
        title: '가족 만들기',
        subtitle: 'Admin Only',
        icon: Icons.favorite_rounded,
        expandChild: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: familyNameController,
              decoration: const InputDecoration(
                labelText: '가족 이름',
                prefixIcon: Icon(Icons.home_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: adminNameController,
              decoration: const InputDecoration(
                labelText: '관리자 이름',
                prefixIcon: Icon(Icons.face_retouching_natural_rounded),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => appState.createFamily(
                  familyName: familyNameController.text,
                  adminName: adminNameController.text,
                ),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('가족 그룹 생성'),
              ),
            ),
          ],
        ),
      ),
      _panel(
        context,
        tint: AppColors.butter.withValues(alpha: 0.42),
        title: '초대로 참여하기',
        subtitle: 'Invite Only',
        icon: Icons.key_rounded,
        expandChild: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: inviteCodeController,
              decoration: const InputDecoration(
                labelText: '초대 코드',
                prefixIcon: Icon(Icons.password_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: memberNameController,
              decoration: const InputDecoration(
                labelText: '이름',
                prefixIcon: Icon(Icons.badge_rounded),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => appState.joinFamily(
                  inviteCode: inviteCodeController.text,
                  memberName: memberNameController.text,
                ),
                icon: const Icon(Icons.favorite_rounded),
                label: const Text('가족 그룹 입장'),
              ),
            ),
          ],
        ),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _hero(context),
              const SizedBox(height: 24),
              if (columns == 1)
                Column(
                  children: <Widget>[
                    for (
                      var index = 0;
                      index < panels.length;
                      index++
                    ) ...<Widget>[
                      panels[index],
                      if (index != panels.length - 1)
                        const SizedBox(height: 18),
                    ],
                  ],
                )
              else
                GridView.count(
                  crossAxisCount: columns,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 18,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: columns == 2 ? 0.95 : 1.02,
                  children: panels,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    return StitchedPanel(
      color: const Color(0xFFFFF1F6),
      padding: const EdgeInsets.all(28),
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const <Widget>[
              CuteTag(
                label: 'pastel kawaii',
                icon: Icons.auto_awesome_rounded,
                color: AppColors.pink,
              ),
              CuteTag(
                label: 'family-friendly',
                icon: Icons.favorite_rounded,
                color: AppColors.sky,
              ),
              CuteTag(
                label: 'soft & cute',
                icon: Icons.stars_rounded,
                color: AppColors.butter,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '가족끼리만 연결되는\n포근한 채팅 공간',
            style: Theme.of(
              context,
            ).textTheme.headlineLarge?.copyWith(fontSize: 40, height: 1.12),
          ),
          const SizedBox(height: 14),
          Text(
            '관리자 초대 코드로만 입장할 수 있고, 가족 전체방과 1:1 대화를 부드럽고 깔끔한 화면에서 사용할 수 있어요.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: const <Widget>[
              _HeroStat(
                icon: Icons.groups_rounded,
                label: 'Family Group',
                tint: AppColors.mint,
              ),
              _HeroStat(
                icon: Icons.chat_bubble_rounded,
                label: 'Rounded Chat',
                tint: AppColors.sky,
              ),
              _HeroStat(
                icon: Icons.favorite_rounded,
                label: 'Soft Mood',
                tint: AppColors.pink,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel(
    BuildContext context, {
    required Color tint,
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
    required bool expandChild,
  }) {
    return StitchedPanel(
      color: tint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CuteTag(label: subtitle, icon: icon, color: AppColors.paper),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontSize: 28),
          ),
          const SizedBox(height: 18),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }

  Widget _emptySavedProfiles(BuildContext context) {
    return StitchedPanel(
      color: AppColors.paper,
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(AppRadii.md),
      shadows: const <BoxShadow>[],
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.sky,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.favorite_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '이 기기에 저장된 프로필이 아직 없어요.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.label,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: AppColors.plum),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
