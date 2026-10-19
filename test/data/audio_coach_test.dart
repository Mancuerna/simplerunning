import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplerunning/data/audio_coach.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('simplerunning/coach');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('speech uses original cues; disabled voice uses distinct countdown and transition beeps', () async {
    final coach = AudioCoach();
    await coach.cue('Recupera · tanda 2 de 4', haptics: false);
    expect(calls.single.method, 'speak');
    expect(calls.single.arguments, 'Recupera · tanda 2 de 4');
    await coach.cue('Sesión guardada', voice: false, haptics: false);
    expect(calls.last.method, 'beep');
    expect(calls.last.arguments, 'transition');
    await coach.cue('3', voice: false, haptics: false, countdown: true);
    expect(calls.last.method, 'beep');
    expect(calls.last.arguments, 'countdown');
    await coach.cue('2', haptics: false, countdown: true);
    expect(calls.last.method, 'speak');
    expect(calls.last.arguments, '2');
    expect(calls, hasLength(4));
    await coach.stop();
    expect(calls.last.method, 'stop');
  });
}
