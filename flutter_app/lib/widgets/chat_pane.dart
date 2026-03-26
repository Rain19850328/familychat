import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/design_tokens.dart';
import 'common.dart';

class ChatPane extends StatefulWidget {
  const ChatPane({
    super.key,
    required this.appState,
    required this.composerController,
    required this.onOpenDrawer,
  });

  final FamilyChatAppState appState;
  final TextEditingController composerController;
  final VoidCallback onOpenDrawer;

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  late final FocusNode _composerFocusNode;
  late final FocusNode _sendButtonFocusNode;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _composerFocusNode = FocusNode();
    _sendButtonFocusNode = FocusNode(
      debugLabel: 'send-button',
      canRequestFocus: false,
      skipTraversal: true,
    );
    _composerFocusNode.addListener(_syncComposerState);
    widget.composerController.addListener(_syncComposerState);
  }

  @override
  void dispose() {
    widget.composerController.removeListener(_syncComposerState);
    _composerFocusNode.removeListener(_syncComposerState);
    widget.appState.setComposerActive(false);
    _sendButtonFocusNode.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  void _syncComposerState() {
    final composing = widget.composerController.value.composing.isValid;
    widget.appState.setComposerActive(_composerFocusNode.hasFocus || composing);
  }

  Future<void> _handleSendPressed() async {
    if (_isSending) {
      return;
    }

    final draft = widget.composerController.text;
    final hasPendingImage = widget.appState.pendingImageDataUrl != null;
    if (draft.trim().isEmpty && !hasPendingImage) {
      return;
    }

    setState(() {
      _isSending = true;
    });
    widget.composerController.clear();

    final sent = await widget.appState.sendMessage(draft);
    if (!mounted) {
      return;
    }

    if (!sent && widget.composerController.text.isEmpty) {
      widget.composerController.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }

    setState(() {
      _isSending = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _composerFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final family = appState.family;
    final member = appState.currentMember;
    final room = appState.activeRoom;
    if (family == null || member == null || room == null) {
      return const Center(child: Text('가족 정보를 불러오는 중입니다.'));
    }

    final messages = appState.activeMessages;
    final muted = room.mutedBy[member.id] == true;

    return StitchedPanel(
      color: AppColors.paper.withValues(alpha: 0.96),
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: Column(
        children: <Widget>[
          _ChatHeader(
            title: roomTitle(room, family, member.id, family.members),
            isMuted: muted,
            onOpenDrawer: widget.onOpenDrawer,
            onToggleMute: appState.toggleMute,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StitchedPanel(
              color: const Color(0xFFFFF7FB),
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: messages.isEmpty
                  ? const _EmptyChatState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      reverse: true,
                      itemCount: messages.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final message = messages[messages.length - 1 - index];
                        final isMine = message.senderId == member.id;
                        final sender = family.members
                            .where((item) => item.id == message.senderId)
                            .firstOrNull;

                        if (message.type == 'system') {
                          return Center(
                            child: CuteTag(
                              label: message.text,
                              icon: Icons.auto_awesome_rounded,
                              color: AppColors.sky,
                            ),
                          );
                        }

                        return _MessageBubble(
                          message: message,
                          senderName: sender?.name,
                          isMine: isMine,
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 14),
          if (appState.pendingImageDataUrl != null)
            _PendingImageStrip(
              imageUrl: appState.pendingImageDataUrl!,
              imageName: appState.pendingImageName ?? '선택한 이미지',
              onClear: appState.clearPendingImage,
            ),
          if (appState.pendingImageDataUrl != null) const SizedBox(height: 12),
          _ComposerBar(
            focusNode: _composerFocusNode,
            sendButtonFocusNode: _sendButtonFocusNode,
            controller: widget.composerController,
            isSending: _isSending,
            onPickImage: _isSending ? null : appState.pickComposerImage,
            onSend: _handleSendPressed,
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.title,
    required this.isMuted,
    required this.onOpenDrawer,
    required this.onToggleMute,
  });

  final String title;
  final bool isMuted;
  final VoidCallback onOpenDrawer;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 980;
    return StitchedPanel(
      color: const Color(0xFFF7F0FF),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          if (isCompact)
            IconButton.filledTonal(
              onPressed: onOpenDrawer,
              icon: const Icon(Icons.menu_rounded),
            ),
          if (isCompact) const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const <Widget>[
                    CuteTag(
                      label: 'Room',
                      icon: Icons.chat_bubble_rounded,
                      color: AppColors.sky,
                    ),
                    CuteTag(
                      label: 'soft chat',
                      icon: Icons.favorite_rounded,
                      color: AppColors.pink,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(fontSize: 30),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: onToggleMute,
            icon: Icon(
              isMuted
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_active_rounded,
            ),
            label: Text(isMuted ? '알림 꺼짐' : '알림 켜짐'),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.senderName,
    required this.isMine,
  });

  final MessageRecord message;
  final String? senderName;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine
        ? const Color(0xFFE6DAFF)
        : const Color(0xFFFFF4F8);
    final accent = isMine ? AppColors.lavenderDeep : AppColors.pinkDeep;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            StitchedPanel(
              color: bubbleColor,
              borderColor: Color.lerp(accent, Colors.white, 0.42)!,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              borderRadius: BorderRadius.circular(30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (!isMine && senderName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        senderName!,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: accent),
                      ),
                    ),
                  if (message.imageDataUrl != null) ...<Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.network(
                        message.imageDataUrl!,
                        fit: BoxFit.cover,
                      ),
                    ),
                    if (message.text.isNotEmpty) const SizedBox(height: 10),
                  ],
                  if (message.text.isNotEmpty)
                    Text(
                      message.text,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: AppColors.ink),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        isMine
                            ? Icons.favorite_rounded
                            : Icons.auto_awesome_rounded,
                        size: 14,
                        color: accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat(
                          'M.d HH:mm',
                        ).format(message.createdAt.toLocal()),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 18,
              left: isMine ? null : -6,
              right: isMine ? -6 : null,
              child: Icon(
                Icons.favorite_rounded,
                size: 14,
                color: accent.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: AppColors.butter.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(32),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.favorite_rounded,
                size: 42,
                color: AppColors.plum,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '아직 대화가 없어요',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              '첫 메시지를 보내서 포근한 가족 채팅을 시작해 보세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingImageStrip extends StatelessWidget {
  const _PendingImageStrip({
    required this.imageUrl,
    required this.imageName,
    required this.onClear,
  });

  final String imageUrl;
  final String imageName;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return StitchedPanel(
      color: AppColors.butter.withValues(alpha: 0.42),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.network(
              imageUrl,
              width: 88,
              height: 88,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const CuteTag(
                  label: '이미지 첨부',
                  icon: Icons.photo_library_rounded,
                  color: AppColors.paper,
                ),
                const SizedBox(height: 10),
                Text(imageName, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.focusNode,
    required this.sendButtonFocusNode,
    required this.controller,
    required this.isSending,
    required this.onPickImage,
    required this.onSend,
  });

  final FocusNode focusNode;
  final FocusNode sendButtonFocusNode;
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback? onPickImage;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return StitchedPanel(
      color: const Color(0xFFFFF9ED),
      padding: const EdgeInsets.all(10),
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: TextFieldTapRegion(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            IconButton.filledTonal(
              onPressed: onPickImage,
              icon: const Icon(Icons.add_photo_alternate_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                focusNode: focusNode,
                controller: controller,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: '메시지를 입력해 주세요',
                  prefixIcon: Icon(Icons.favorite_rounded),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              focusNode: sendButtonFocusNode,
              onPressed: isSending ? null : onSend,
              style: FilledButton.styleFrom(
                minimumSize: const Size(92, 56),
                backgroundColor: AppColors.pinkDeep,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    isSending
                        ? Icons.more_horiz_rounded
                        : Icons.send_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text('전송'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
