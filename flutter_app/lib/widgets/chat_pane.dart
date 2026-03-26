import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
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
    final sent = await widget.appState.sendMessage(widget.composerController.text);
    if (!sent || !mounted) {
      return;
    }

    widget.composerController.clear();

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

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFCF5), Color(0xFFF7F3EA)],
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Row(
                children: [
                  if (MediaQuery.sizeOf(context).width < 980)
                    IconButton(
                      onPressed: widget.onOpenDrawer,
                      icon: const Icon(Icons.menu_rounded),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Room',
                          style: TextStyle(color: Color(0xFF4A746C), fontWeight: FontWeight.w700),
                        ),
                        Text(
                          roomTitle(room, family, member.id, family.members),
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: appState.toggleMute,
                    icon: Icon(muted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded),
                    label: Text(muted ? '알림 꺼짐' : '알림 켜짐'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: messages.isEmpty
                ? const Center(child: Text('아직 메시지가 없습니다. 첫 메시지를 보내 보세요.'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                    reverse: true,
                    itemCount: messages.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      final isMine = message.senderId == member.id;
                      final sender = family.members.where((item) => item.id == message.senderId).firstOrNull;

                      if (message.type == 'system') {
                        return Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE7F4EE),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(message.text),
                          ),
                        );
                      }

                      return Align(
                        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: isMine ? const Color(0xFF0E7A6B) : Colors.white,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isMine && sender != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        sender.name,
                                        style: const TextStyle(color: Color(0xFF4A746C), fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  if (message.imageDataUrl != null) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: Image.network(message.imageDataUrl!, fit: BoxFit.cover),
                                    ),
                                    if (message.text.isNotEmpty) const SizedBox(height: 10),
                                  ],
                                  if (message.text.isNotEmpty)
                                    Text(
                                      message.text,
                                      style: TextStyle(color: isMine ? Colors.white : Colors.black87, height: 1.45),
                                    ),
                                  const SizedBox(height: 8),
                                  Text(
                                    DateFormat('M.d HH:mm').format(message.createdAt.toLocal()),
                                    style: TextStyle(
                                      color: isMine ? Colors.white70 : Colors.black45,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              children: [
                if (appState.pendingImageDataUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            appState.pendingImageDataUrl!,
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(appState.pendingImageName ?? '선택한 이미지')),
                        IconButton(
                          onPressed: appState.clearPendingImage,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(color: Color(0x11000000), blurRadius: 18, offset: Offset(0, 8)),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: appState.pickComposerImage,
                          icon: const Icon(Icons.add_photo_alternate_rounded),
                        ),
                        Expanded(
                          child: TextField(
                            focusNode: _composerFocusNode,
                            controller: widget.composerController,
                            minLines: 1,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              hintText: '메시지를 입력해 주세요',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        FilledButton(
                          focusNode: _sendButtonFocusNode,
                          onPressed: _handleSendPressed,
                          child: const Text('전송'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
