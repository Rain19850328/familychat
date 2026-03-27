import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui/design_tokens.dart';
import 'widgets/chat_pane.dart';
import 'widgets/onboarding_pane.dart';
import 'widgets/common.dart';
import 'widgets/sidebar.dart';

class FamilyChatHome extends StatefulWidget {
  const FamilyChatHome({super.key, required this.appState});

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
    if (mounted) {
      if (!widget.appState.hasSession) {
        _clearTransientState();
      }
      setState(() {});
    }
    final pushHelp = widget.appState.pendingPushHelp;
    if (mounted && pushHelp != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          return;
        }
        widget.appState.clearPendingPushHelp();
        await showPushPermissionHelpDialog(context, pushHelp);
      });
    }
    final toast = widget.appState.toastMessage;
    if (!mounted || toast == null || toast.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast)));
    widget.appState.clearToast();
  }

  void _clearTransientState() {
    _familyNameController.clear();
    _adminNameController.clear();
    _inviteCodeController.clear();
    _memberNameController.clear();
    _composerController.clear();
    ScaffoldMessenger.of(context).clearSnackBars();
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final isDesktop = MediaQuery.sizeOf(context).width >= 980;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      drawerScrimColor: AppColors.plum.withValues(alpha: 0.18),
      drawer: isDesktop
          ? null
          : Drawer(
              child: SafeArea(
                minimum: const EdgeInsets.all(10),
                child: Sidebar(
                  appState: appState,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            ),
      body: CozyBackdrop(
        child: Stack(
          children: <Widget>[
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: appState.hasSession
                    ? (isDesktop
                          ? Row(
                              children: <Widget>[
                                SizedBox(
                                  width: 360,
                                  child: Sidebar(appState: appState),
                                ),
                                const SizedBox(width: 14),
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
                              onOpenDrawer: () =>
                                  _scaffoldKey.currentState?.openDrawer(),
                            ))
                    : OnboardingPane(
                        appState: appState,
                        familyNameController: _familyNameController,
                        adminNameController: _adminNameController,
                        inviteCodeController: _inviteCodeController,
                        memberNameController: _memberNameController,
                      ),
              ),
            ),
            if (appState.isBusy)
              Positioned.fill(
                child: ColoredBox(
                  color: AppColors.plum.withValues(alpha: 0.08),
                  child: const Center(
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        color: AppColors.lavenderDeep,
                        backgroundColor: AppColors.pink,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
