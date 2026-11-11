import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'device.dart';

const voiceSampleRate = 16000;

/// The recognizer hears 30 s at a time, so a recording is cut into 30 s
/// chunks: each finished chunk is transcribed while listening goes on.
/// There is no cap on the recording itself (P10.3).
const voiceChunkDuration = Duration(seconds: 30);
const voiceChunkSamples = voiceSampleRate * 30;

class VoicePermissionDenied implements Exception {
  const VoicePermissionDenied({this.permanent = false});

  final bool permanent;

  @override
  String toString() => permanent
      ? 'Microphone access is blocked. Allow it in Android app settings.'
      : 'Microphone permission is required for local voice input.';
}

enum VoiceRecorderEvent { interrupted }

abstract interface class VoiceRecorder {
  Stream<VoiceRecorderEvent> get events;
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> cancel();
  Future<void> dispose();
}

/// AgentPhone ships without the microphone permission, so there is no
/// recorder behind this interface: starting one always fails with
/// [VoicePermissionDenied]. The interface stays so the voice controller, the
/// transcription pipeline and their tests keep their shape, and so a future
/// build that wants the microphone only has to fill this one class in.
class RecordVoiceRecorder implements VoiceRecorder {
  RecordVoiceRecorder({VoiceDevicePlatform platform = voiceDevicePlatform});

  final _events = StreamController<VoiceRecorderEvent>.broadcast();

  @override
  Stream<VoiceRecorderEvent> get events => _events.stream;

  @override
  Future<Stream<Uint8List>> start() async {
    throw const VoicePermissionDenied(permanent: true);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async => _events.close();
}

class Pcm16Accumulator {
  Pcm16Accumulator({this.maximumSamples = voiceChunkSamples})
    : _samples = Float32List(maximumSamples);

  final int maximumSamples;
  final Float32List _samples;
  int _length = 0;
  int? _pendingLowByte;
  double level = 0;

  int get length => _length;
  bool get isFull => _length >= maximumSamples;
  Duration get duration =>
      Duration(microseconds: (_length * 1000000) ~/ voiceSampleRate);

  /// Adds PCM16 bytes from [start] until the buffer is full and returns
  /// how many bytes it took; the rest belongs to the next chunk.
  int add(Uint8List bytes, [int start = 0]) {
    if (start >= bytes.length || isFull) return 0;
    var index = start;
    var sumSquares = 0.0;
    var levelSamples = 0;
    if (_pendingLowByte != null && index < bytes.length) {
      final value = _decode(_pendingLowByte!, bytes[index++]);
      _pendingLowByte = null;
      _samples[_length++] = value;
      sumSquares += value * value;
      levelSamples++;
    }
    while (index + 1 < bytes.length && !isFull) {
      final value = _decode(bytes[index], bytes[index + 1]);
      index += 2;
      _samples[_length++] = value;
      sumSquares += value * value;
      levelSamples++;
    }
    if (!isFull && index < bytes.length) _pendingLowByte = bytes[index++];
    if (levelSamples > 0) {
      level = math.sqrt(sumSquares / levelSamples).clamp(0, 1);
    }
    return index - start;
  }

  double _decode(int low, int high) {
    var signed = low | (high << 8);
    if (signed >= 0x8000) signed -= 0x10000;
    return signed / 32768.0;
  }

  Float32List takeSamples() {
    final result = Float32List(_length)..setRange(0, _length, _samples);
    clear();
    return result;
  }

  void clear() {
    _samples.fillRange(0, _length, 0);
    _length = 0;
    _pendingLowByte = null;
    level = 0;
  }
}
