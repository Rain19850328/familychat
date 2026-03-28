// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

const int kVoiceSampleRate = 16000;
const int kVoiceChannels = 1;
const int kVoiceBitsPerSample = 16;
const int kVoiceMessageMaxDurationMs = 30000;

class ToneStep {
  const ToneStep(this.frequencyHz, this.durationMs, {this.volume = 0.28});

  final double? frequencyHz;
  final int durationMs;
  final double volume;
}

Uint8List encodePcm16Wav(
  Uint8List pcmBytes, {
  int sampleRate = kVoiceSampleRate,
  int channels = kVoiceChannels,
  int bitsPerSample = kVoiceBitsPerSample,
}) {
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final dataLength = pcmBytes.length;
  final totalLength = 44 + dataLength;
  final bytes = BytesBuilder(copy: false);

  void writeAscii(String value) {
    bytes.add(ascii.encode(value));
  }

  void writeUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void writeUint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  writeAscii('RIFF');
  writeUint32(totalLength - 8);
  writeAscii('WAVE');
  writeAscii('fmt ');
  writeUint32(16);
  writeUint16(1);
  writeUint16(channels);
  writeUint32(sampleRate);
  writeUint32(byteRate);
  writeUint16(blockAlign);
  writeUint16(bitsPerSample);
  writeAscii('data');
  writeUint32(dataLength);
  bytes.add(pcmBytes);

  return bytes.toBytes();
}

String encodeAudioDataUrl(Uint8List wavBytes) {
  return 'data:audio/wav;base64,${base64Encode(wavBytes)}';
}

Uint8List? decodeAudioDataUrl(String? dataUrl) {
  if (dataUrl == null || dataUrl.isEmpty) {
    return null;
  }
  final commaIndex = dataUrl.indexOf(',');
  if (commaIndex < 0 || commaIndex + 1 >= dataUrl.length) {
    return null;
  }
  return base64Decode(dataUrl.substring(commaIndex + 1));
}

int estimatePcm16DurationMs(
  Uint8List pcmBytes, {
  int sampleRate = kVoiceSampleRate,
  int channels = kVoiceChannels,
  int bitsPerSample = kVoiceBitsPerSample,
}) {
  final bytesPerSecond = sampleRate * channels * bitsPerSample ~/ 8;
  if (bytesPerSecond <= 0) {
    return 0;
  }
  return ((pcmBytes.length / bytesPerSecond) * 1000).round();
}

Uint8List synthesizeToneSequenceWav(
  List<ToneStep> steps, {
  int sampleRate = kVoiceSampleRate,
}) {
  final pcm = BytesBuilder(copy: false);
  for (final step in steps) {
    final sampleCount = (sampleRate * step.durationMs / 1000).round();
    for (var i = 0; i < sampleCount; i++) {
      final sample = step.frequencyHz == null
          ? 0.0
          : math.sin(2 * math.pi * step.frequencyHz! * i / sampleRate) *
                step.volume;
      final value = (sample * 32767).round().clamp(-32768, 32767);
      final data = ByteData(2)..setInt16(0, value, Endian.little);
      pcm.add(data.buffer.asUint8List());
    }
  }
  return encodePcm16Wav(
    pcm.toBytes(),
    sampleRate: sampleRate,
    channels: 1,
    bitsPerSample: kVoiceBitsPerSample,
  );
}

class MemoryAudioSource extends StreamAudioSource {
  MemoryAudioSource(this.bytes, {this.contentType = 'audio/wav'});

  final Uint8List bytes;
  final String contentType;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final safeStart = start ?? 0;
    final safeEnd = end ?? bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: safeEnd - safeStart,
      offset: safeStart,
      contentType: contentType,
      stream: Stream<List<int>>.value(bytes.sublist(safeStart, safeEnd)),
    );
  }
}
