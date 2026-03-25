import 'package:flutter/material.dart';

import 'app_state.dart';
import 'widgets/chat_pane.dart';
import 'widgets/onboarding_pane.dart';
import 'widgets/sidebar.dart';

class FamilyChatHome extends StatefulWidget {
  const FamilyChatHome({
    super.key,
    required this.appState,
  });

  final FamilyChatAppState appState;

  @override
  State<FamilyChatHome> createState() => _FamilyChatHomeState();
}

class _FamilyChatHomeState extends State<FamilyChatHome> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _familyNameController = TextEditingController();
  final TextEditingController _adminNameController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();
  final TextEditingController _memberNameController = TextEditingController();
  final TextEditingController _composerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_handleStateChange);
  }

  @override
  void dispose() {
    widget.appState.removeListener(_handleStateChange);
    _familyNameController.dispose();
    _adminNameController.dispose();
    _inviteCodeController.dispose();
    _memberNameController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  void _handleStateChange() {
    final toast = widget.appState.toastMessage;
    if (!mounted || toast == null || toast.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast)));
    widget.appState.clearToast();
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final isDesktop = MediaQuery.sizeOf(context).width >= 980;

    return Scaffold(
      key: _scaffoldKey,
      drawer: isDesktop ? null : Drawer(child: Sidebar(appState: appState, onClose: () => Navigator.of(context).pop())),
      body: Stack(
        children: [
          SafeArea(
            child: appState.hasSession
                ? (isDesktop
                    ? Row(
                        children: [
                          SizedBox(width: 340, child: Sidebar(appState: appState)),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: ChatPane(
                              appState: appState,
                              composerController: _composerController,
                              onOpenDrawer: () {},
                            ),
                          ),
                        ],
                      )
                    : ChatPane(
                        appState: appState,
                        composerController: _composerController,
                        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
                      ))
                : OnboardingPane(
                    appState: appState,
                    familyNameController: _familyNameController,
                    adminNameController: _adminNameController,
                    inviteCodeController: _inviteCodeController,
                    memberNameController: _memberNameController,
                  ),
          ),
          if (appState.isBusy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.08),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
