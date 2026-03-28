import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';
import 'platform/window_interaction.dart';
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

class _FamilyChatHomeState extends State<FamilyChatHome>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _familyNameController = TextEditingController();
  final TextEditingController _adminNameController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();
  final TextEditingController _memberNameController = TextEditingController();
  final TextEditingController _composerController = TextEditingController();
  WindowInteractionObserver? _windowInteractionObserver;
  AppLifecycleState? _lifecycleState;
  bool _windowInteractive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.appState.addListener(_handleStateChange);
    _windowInteractive = currentWindowInteractionState();
    _windowInteractionObserver = observeWindowInteraction((isInteractive) {
      _windowInteractive = isInteractive;
      _syncReadReceiptState();
    });
    _syncReadReceiptState();
  }

  @override
  void dispose() {
    widget.appState.setReadReceiptsActive(false);
    _windowInteractionObserver?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.appState.removeListener(_handleStateChange);
    _familyNameController.dispose();
    _adminNameController.dispose();
    _inviteCodeController.dispose();
    _memberNameController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncReadReceiptState();
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

  void _syncReadReceiptState() {
    final lifecycleInteractive =
        _lifecycleState == null || _lifecycleState == AppLifecycleState.resumed;
    widget.appState.setReadReceiptsActive(
      lifecycleInteractive && _windowInteractive,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final isDesktop = MediaQuery.sizeOf(context).width >= 980;
    final overlayRoom = appState.voiceCallOverlayRoom;
    final overlayCaller = appState.voiceCallOverlayCaller;
    final currentMember = appState.currentMember;
    final family = appState.family;

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
            if (overlayRoom != null && family != null && currentMember != null)
              Positioned.fill(
                child: _IncomingVoiceCallOverlay(
                  appState: appState,
                  room: overlayRoom,
                  caller: overlayCaller,
                  roomLabel: roomTitle(
                    overlayRoom,
                    family,
                    currentMember.id,
                    family.members,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IncomingVoiceCallOverlay extends StatelessWidget {
  const _IncomingVoiceCallOverlay({
    required this.appState,
    required this.room,
    required this.caller,
    required this.roomLabel,
  });

  final FamilyChatAppState appState;
  final RoomRecord room;
  final MemberRecord? caller;
  final String roomLabel;

  @override
  Widget build(BuildContext context) {
    final isIncoming = appState.isVoiceCallOverlayIncoming;
    final isConnecting =
        appState.isVoiceCallConnecting &&
        appState.voiceCallOverlayRoom?.id == room.id;
    final isJoined =
        appState.isVoiceCallJoined &&
        appState.voiceCallOverlayRoom?.id == room.id;
    final callerName = caller?.name ?? roomLabel;
    final theme = Theme.of(context);

    return ColoredBox(
      color: AppColors.plum.withValues(alpha: 0.18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: StitchedPanel(
              color: AppColors.creamSoft,
              padding: const EdgeInsets.all(24),
              borderRadius: BorderRadius.circular(AppRadii.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: AppColors.pink.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.call_rounded,
                      size: 36,
                      color: AppColors.pinkDeep,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    isIncoming
                        ? '$callerName님에게 전화가 왔어요'
                        : isJoined
                        ? '음성 통화가 연결되었어요'
                        : '음성 통화에 연결하고 있어요',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  AvatarBadge(
                    name: callerName,
                    avatarKey: caller?.avatarKey,
                    avatarImageDataUrl: caller?.avatarImageDataUrl,
                    size: 72,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    callerName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    roomLabel,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.inkSoft,
                    ),
                  ),
                  if (appState.activeRoomVoiceCallError?.isNotEmpty ==
                      true) ...<Widget>[
                    const SizedBox(height: 14),
                    Text(
                      appState.activeRoomVoiceCallError!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.pinkDeep,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  if (isIncoming)
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: appState.dismissIncomingVoiceCallPrompt,
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('닫기'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: appState.acceptIncomingVoiceCall,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.pinkDeep,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.call_rounded),
                            label: const Text('받기'),
                          ),
                        ),
                      ],
                    )
                  else
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        FilledButton.tonalIcon(
                          onPressed: isConnecting
                              ? null
                              : appState.toggleVoiceMute,
                          icon: Icon(
                            appState.isVoiceCallMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                          ),
                          label: Text(
                            appState.isVoiceCallMuted ? '마이크 켜기' : '마이크 끄기',
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: appState.leaveVoiceCall,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('나가기'),
                        ),
                        FilledButton.icon(
                          onPressed: appState.endActiveRoomVoiceCall,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.pinkDeep,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.call_end_rounded),
                          label: const Text('종료'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
