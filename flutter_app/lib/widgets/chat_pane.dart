import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/design_tokens.dart';
import '../voice_message_support.dart';
import 'common.dart';

const List<String> _composerFontFallback = <String>[
  'Apple SD Gothic Neo',
  'Noto Sans KR',
  'Malgun Gothic',
  'Nanum Gothic',
  'sans-serif',
];

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
  late final AudioRecorder _audioRecorder;
  StreamSubscription<Uint8List>? _recordingSubscription;
  BytesBuilder? _recordedPcmChunks;
  Stopwatch? _recordingStopwatch;
  Timer? _recordingTicker;
  bool _isSending = false;
  bool _isRecording = false;
  int _recordingDurationMs = 0;

  @override
  void initState() {
    super.initState();
    _composerFocusNode = FocusNode();
    _sendButtonFocusNode = FocusNode(
      debugLabel: 'send-button',
      canRequestFocus: false,
      skipTraversal: true,
    );
    _audioRecorder = AudioRecorder();
    _composerFocusNode.addListener(_syncComposerState);
    widget.composerController.addListener(_syncComposerState);
  }

  @override
  void dispose() {
    _recordingTicker?.cancel();
    unawaited(_recordingSubscription?.cancel() ?? Future<void>.value());
    unawaited(_audioRecorder.dispose());
    widget.composerController.removeListener(_syncComposerState);
    _composerFocusNode.removeListener(_syncComposerState);
    widget.appState.setComposerActive(false);
    _sendButtonFocusNode.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  void _syncComposerState() {
    final composing = widget.composerController.value.composing.isValid;
    widget.appState.setComposerActive(composing);
  }

  Future<void> _handleSendPressed() async {
    if (_isSending) {
      return;
    }

    final pressedAt = DateTime.now();
    final draft = widget.composerController.text;
    final hasPendingImage = widget.appState.pendingImageDataUrl != null;
    if (draft.trim().isEmpty && !hasPendingImage) {
      return;
    }

    setState(() {
      _isSending = true;
    });
    widget.composerController.clear();

    final sent = await widget.appState.sendMessage(
      draft,
      initiatedAt: pressedAt,
    );
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

  Future<void> _toggleVoiceRecording() async {
    if (_isSending) {
      return;
    }
    if (_isRecording) {
      await _finishVoiceRecording();
      return;
    }

    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('마이크 권한을 허용해 주세요.')));
      return;
    }

    try {
      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: kVoiceSampleRate,
          numChannels: kVoiceChannels,
        ),
      );
      _recordedPcmChunks = BytesBuilder(copy: false);
      _recordingStopwatch = Stopwatch()..start();
      _recordingSubscription = stream.listen((chunk) {
        _recordedPcmChunks?.add(chunk);
      });
      _recordingTicker?.cancel();
      _recordingTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted || _recordingStopwatch == null) {
          return;
        }
        final elapsed = _recordingStopwatch!.elapsedMilliseconds;
        if (elapsed >= kVoiceMessageMaxDurationMs) {
          unawaited(_finishVoiceRecording());
          return;
        }
        setState(() {
          _recordingDurationMs = elapsed;
        });
      });
      setState(() {
        _isRecording = true;
        _recordingDurationMs = 0;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('음성 녹음을 시작하지 못했습니다.')));
    }
  }

  Future<void> _finishVoiceRecording() async {
    if (!_isRecording) {
      return;
    }

    final pressedAt = DateTime.now();
    final stopwatch = _recordingStopwatch;
    final elapsedMs = stopwatch?.elapsedMilliseconds ?? _recordingDurationMs;
    stopwatch?.stop();
    _recordingTicker?.cancel();
    _recordingTicker = null;
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    await _audioRecorder.stop();
    final pcmBytes = _recordedPcmChunks?.toBytes() ?? Uint8List(0);
    _recordedPcmChunks = null;

    setState(() {
      _isRecording = false;
      _recordingDurationMs = 0;
      _isSending = true;
    });

    final estimatedDurationMs = estimatePcm16DurationMs(pcmBytes);
    final durationMs = estimatedDurationMs > 0
        ? estimatedDurationMs
        : elapsedMs;

    if (pcmBytes.isEmpty || durationMs < 300) {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('너무 짧아서 음성 메시지를 보내지 않았습니다.')),
        );
      }
      return;
    }

    final wavBytes = encodePcm16Wav(pcmBytes);
    final sent = await widget.appState.sendVoiceMessage(
      wavBytes,
      durationMs: durationMs,
      initiatedAt: pressedAt,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _isSending = false;
    });

    if (!sent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('음성 메시지를 보내지 못했습니다.')));
    }
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: _ChatHeader(
            title: roomTitle(room, family, member.id, family.members),
            isMuted: muted,
            isVoiceCallActive: room.voiceCallActive,
            isVoiceCallConnecting: appState.isActiveRoomVoiceCallConnecting,
            isVoiceCallJoined: appState.isActiveRoomVoiceCallJoined,
            isVoiceCallMuted: appState.isActiveRoomVoiceCallMuted,
            onOpenDrawer: widget.onOpenDrawer,
            onToggleMute: appState.toggleMute,
            onStartOrJoinVoiceCall: appState.startOrJoinVoiceCall,
            onToggleVoiceMute: appState.toggleVoiceMute,
            onLeaveVoiceCall: appState.leaveVoiceCall,
            onEndVoiceCall: appState.endActiveRoomVoiceCall,
          ),
        ),
        if (room.voiceCallActive ||
            appState.isActiveRoomVoiceCallConnecting ||
            appState.isActiveRoomVoiceCallJoined ||
            (appState.activeRoomVoiceCallError?.isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: _VoiceCallBanner(
              isActive: room.voiceCallActive,
              isConnecting: appState.isActiveRoomVoiceCallConnecting,
              isJoined: appState.isActiveRoomVoiceCallJoined,
              participantCount: appState.activeRoomVoiceParticipantCount,
              isAutoplayBlocked: appState.isActiveRoomVoiceAutoplayBlocked,
              errorText: appState.activeRoomVoiceCallError,
              onRetryAudio: appState.retryVoiceAudioPlayback,
            ),
          ),
        Expanded(
          child: messages.isEmpty
              ? const _EmptyChatState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
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
                      currentMemberId: member.id,
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        if (appState.pendingImageDataUrl != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PendingImageStrip(
              imageUrl: appState.pendingImageDataUrl!,
              imageName: appState.pendingImageName ?? '선택한 이미지',
              onClear: appState.clearPendingImage,
            ),
          ),
        _ComposerBar(
          focusNode: _composerFocusNode,
          sendButtonFocusNode: _sendButtonFocusNode,
          controller: widget.composerController,
          isSending: _isSending,
          isRecording: _isRecording,
          recordingDurationMs: _recordingDurationMs,
          onPickImage: _isSending ? null : appState.pickComposerImage,
          onToggleRecording: _toggleVoiceRecording,
          onSend: _handleSendPressed,
        ),
      ],
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.title,
    required this.isMuted,
    required this.isVoiceCallActive,
    required this.isVoiceCallConnecting,
    required this.isVoiceCallJoined,
    required this.isVoiceCallMuted,
    required this.onOpenDrawer,
    required this.onToggleMute,
    required this.onStartOrJoinVoiceCall,
    required this.onToggleVoiceMute,
    required this.onLeaveVoiceCall,
    required this.onEndVoiceCall,
  });

  final String title;
  final bool isMuted;
  final bool isVoiceCallActive;
  final bool isVoiceCallConnecting;
  final bool isVoiceCallJoined;
  final bool isVoiceCallMuted;
  final VoidCallback onOpenDrawer;
  final VoidCallback onToggleMute;
  final VoidCallback onStartOrJoinVoiceCall;
  final VoidCallback onToggleVoiceMute;
  final VoidCallback onLeaveVoiceCall;
  final VoidCallback onEndVoiceCall;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 980;
    return Row(
      children: <Widget>[
        if (isCompact)
          IconButton.filledTonal(
            onPressed: onOpenDrawer,
            icon: const Icon(Icons.menu_rounded),
          ),
        if (isCompact) const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontSize: 30),
          ),
        ),
        IconButton.filledTonal(
          onPressed: isVoiceCallConnecting ? null : onStartOrJoinVoiceCall,
          style: IconButton.styleFrom(
            backgroundColor: isVoiceCallActive
                ? AppColors.pinkDeep
                : AppColors.sky,
            foregroundColor: Colors.white,
          ),
          icon: Icon(
            isVoiceCallConnecting
                ? Icons.more_horiz_rounded
                : isVoiceCallJoined
                ? Icons.phone_in_talk_rounded
                : isVoiceCallActive
                ? Icons.call_rounded
                : Icons.add_call,
          ),
          tooltip: isVoiceCallJoined
              ? 'In voice call'
              : isVoiceCallActive
              ? 'Join voice call'
              : 'Start voice call',
        ),
        if (isVoiceCallJoined) ...<Widget>[
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: onToggleVoiceMute,
            style: IconButton.styleFrom(
              backgroundColor: isVoiceCallMuted
                  ? AppColors.butter
                  : AppColors.lavender,
              foregroundColor: AppColors.plum,
            ),
            icon: Icon(
              isVoiceCallMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            ),
            tooltip: isVoiceCallMuted ? 'Unmute microphone' : 'Mute microphone',
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: onLeaveVoiceCall,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.paper,
              foregroundColor: AppColors.plum,
            ),
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Leave voice call',
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: onEndVoiceCall,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.pinkDeep,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.call_end_rounded),
            tooltip: 'End voice call',
          ),
          const SizedBox(width: 8),
        ],
        IconButton.filledTonal(
          onPressed: onToggleMute,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.lavenderDeep,
            foregroundColor: Colors.white,
          ),
          icon: Icon(
            isMuted
                ? Icons.notifications_off_rounded
                : Icons.notifications_active_rounded,
          ),
          tooltip: isMuted ? '알림 꺼짐' : '알림 켜짐',
        ),
      ],
    );
  }
}

class _VoiceCallBanner extends StatelessWidget {
  const _VoiceCallBanner({
    required this.isActive,
    required this.isConnecting,
    required this.isJoined,
    required this.participantCount,
    required this.isAutoplayBlocked,
    required this.errorText,
    required this.onRetryAudio,
  });

  final bool isActive;
  final bool isConnecting;
  final bool isJoined;
  final int participantCount;
  final bool isAutoplayBlocked;
  final String? errorText;
  final VoidCallback onRetryAudio;

  @override
  Widget build(BuildContext context) {
    final statusText = isConnecting
        ? 'Connecting voice call...'
        : isJoined
        ? 'Voice call connected'
        : isActive
        ? 'Voice call in progress'
        : 'Voice call unavailable';

    return StitchedPanel(
      color: AppColors.paper,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.sky.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            alignment: Alignment.center,
            child: Icon(
              isJoined ? Icons.phone_in_talk_rounded : Icons.call_rounded,
              color: AppColors.plum,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  statusText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  errorText?.isNotEmpty == true
                      ? errorText!
                      : participantCount > 0
                      ? 'Participants: $participantCount'
                      : 'Tap the call button to join the room voice call.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (isAutoplayBlocked)
            FilledButton.tonalIcon(
              onPressed: onRetryAudio,
              icon: const Icon(Icons.volume_up_rounded),
              label: const Text('Enable audio'),
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
    required this.currentMemberId,
  });

  final MessageRecord message;
  final String? senderName;
  final bool isMine;
  final String currentMemberId;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine
        ? const Color(0xFFE6DAFF)
        : const Color(0xFFFFF4F8);
    final accent = isMine ? AppColors.lavenderDeep : AppColors.pinkDeep;
    final readStatus = _readStatusLabel(message, currentMemberId);

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
                  if (message.audioDataUrl != null) ...<Widget>[
                    _AudioMessageTile(
                      audioDataUrl: message.audioDataUrl!,
                      durationMs: message.audioDurationMs,
                      accent: accent,
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
                        DateFormat('HH:mm').format(message.createdAt.toLocal()),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                      if (readStatus != null) ...<Widget>[
                        const SizedBox(width: 8),
                        Text(
                          readStatus,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontSize: 12,
                                color: accent,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
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
              '첫 메시지를 보내서 가족 채팅을 시작해 보세요.',
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
    required this.isRecording,
    required this.recordingDurationMs,
    required this.onPickImage,
    required this.onToggleRecording,
    required this.onSend,
  });

  final FocusNode focusNode;
  final FocusNode sendButtonFocusNode;
  final TextEditingController controller;
  final bool isSending;
  final bool isRecording;
  final int recordingDurationMs;
  final VoidCallback? onPickImage;
  final VoidCallback onToggleRecording;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final composerTextStyle = _composerTextStyle(
      Theme.of(context).platform,
      color: AppColors.ink,
      fontSize: 16,
    );
    final composerHintStyle = _composerTextStyle(
      Theme.of(context).platform,
      color: AppColors.inkSoft,
      fontSize: 15,
    );
    return TextFieldTapRegion(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          IconButton.filledTonal(
            onPressed: isRecording ? null : onPickImage,
            icon: const Icon(Icons.add_photo_alternate_rounded),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: isSending ? null : onToggleRecording,
            style: IconButton.styleFrom(
              backgroundColor: isRecording
                  ? AppColors.pinkDeep
                  : AppColors.lavender,
              foregroundColor: isRecording ? Colors.white : AppColors.plum,
            ),
            icon: Icon(isRecording ? Icons.stop_rounded : Icons.mic_rounded),
            tooltip: isRecording ? 'Stop recording' : 'Record voice message',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9ED),
                borderRadius: BorderRadius.circular(AppRadii.xl),
                boxShadow: AppShadows.plush,
              ),
              child: TextField(
                focusNode: focusNode,
                controller: controller,
                style: composerTextStyle,
                readOnly: isRecording,
                minLines: 1,
                maxLines: 1,
                decoration: InputDecoration(
                  hintText: '메세지입력',
                  hintStyle: composerHintStyle,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            focusNode: sendButtonFocusNode,
            onPressed: isSending || isRecording ? null : onSend,
            style: IconButton.styleFrom(
              minimumSize: const Size(56, 56),
              backgroundColor: AppColors.pinkDeep,
              foregroundColor: Colors.white,
            ),
            icon: Icon(
              isSending ? Icons.more_horiz_rounded : Icons.send,
              size: 26,
            ),
            tooltip: '전송',
          ),
        ],
      ),
    );
  }
}

class _AudioMessageTile extends StatefulWidget {
  const _AudioMessageTile({
    required this.audioDataUrl,
    required this.accent,
    this.durationMs,
  });

  final String audioDataUrl;
  final int? durationMs;
  final Color accent;

  @override
  State<_AudioMessageTile> createState() => _AudioMessageTileState();
}

class _AudioMessageTileState extends State<_AudioMessageTile> {
  late final AudioPlayer _player;
  Duration? _duration;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.durationStream.listen((duration) {
      if (!mounted) {
        return;
      }
      setState(() {
        _duration = duration;
      });
    });
    unawaited(_loadSource());
  }

  @override
  void didUpdateWidget(covariant _AudioMessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioDataUrl != widget.audioDataUrl) {
      unawaited(_loadSource());
    }
  }

  Future<void> _loadSource() async {
    final bytes = decodeAudioDataUrl(widget.audioDataUrl);
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = 'Audio unavailable';
        _duration = null;
      });
      return;
    }

    try {
      await _player.setAudioSource(MemoryAudioSource(bytes));
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = 'Audio unavailable';
      });
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallbackDuration = widget.durationMs == null
        ? Duration.zero
        : Duration(milliseconds: widget.durationMs!);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          builder: (context, stateSnapshot) {
            final isPlaying = stateSnapshot.data?.playing ?? false;
            return Row(
              children: <Widget>[
                IconButton.filledTonal(
                  onPressed: _loadError != null
                      ? null
                      : () async {
                          if (isPlaying) {
                            await _player.pause();
                            return;
                          }
                          final duration = _player.duration ?? Duration.zero;
                          if (_player.position >= duration &&
                              duration > Duration.zero) {
                            await _player.seek(Duration.zero);
                          }
                          await _player.play();
                        },
                  style: IconButton.styleFrom(
                    backgroundColor: widget.accent.withValues(alpha: 0.16),
                    foregroundColor: widget.accent,
                  ),
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _loadError ?? 'Voice message',
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: AppColors.ink),
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<Duration>(
                        stream: _player.positionStream,
                        builder: (context, positionSnapshot) {
                          final position =
                              positionSnapshot.data ?? Duration.zero;
                          final duration = _duration ?? fallbackDuration;
                          final denominator = duration.inMilliseconds <= 0
                              ? 1
                              : duration.inMilliseconds;
                          final progress =
                              (position.inMilliseconds / denominator)
                                  .clamp(0, 1)
                                  .toDouble();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 8,
                                  backgroundColor: widget.accent.withValues(
                                    alpha: 0.14,
                                  ),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    widget.accent,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_formatDuration(position.inMilliseconds)} / ${_formatDuration(duration.inMilliseconds)}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontSize: 12,
                                      color: AppColors.inkSoft,
                                    ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String? _readStatusLabel(MessageRecord message, String currentMemberId) {
  if (message.senderId == null || message.senderId != currentMemberId) {
    return null;
  }

  final readCount = message.readBy.keys
      .where((memberId) => memberId != message.senderId)
      .length;
  if (readCount <= 0) {
    return '안읽음';
  }
  return readCount == 1 ? '읽음' : '읽음 $readCount';
}

String _formatDuration(int durationMs) {
  final duration = Duration(milliseconds: durationMs);
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

TextStyle _composerTextStyle(
  TargetPlatform platform, {
  required Color color,
  required double fontSize,
}) {
  final fontFamily = switch (platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => 'Apple SD Gothic Neo',
    TargetPlatform.android => 'Noto Sans KR',
    TargetPlatform.windows => 'Malgun Gothic',
    _ => null,
  };
  return TextStyle(
    fontFamily: kIsWeb ? null : fontFamily,
    fontFamilyFallback: _composerFontFallback,
    color: color,
    fontSize: fontSize,
    height: 1.2,
  );
}
