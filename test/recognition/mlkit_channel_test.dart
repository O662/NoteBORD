import 'dart:async';

import 'package:endless/recognition/recognizer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The Dart side of android/…/InkRecognition.kt (channel `endless/ink`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(MlKitInkRecognizer.channelName);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('checks, downloads and reads with the arguments the Android side expects', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'check' || 'download' => true,
        'recognize' => ['momentum', 'momenta'],
        _ => null,
      };
    });
    final r = MlKitInkRecognizer();
    expect(await r.hasModel('en-US'), isTrue);
    expect(await r.downloadModel('en-US'), isTrue);
    final read = await r.recognize(
      [
        [(x: 1.0, y: 2.0, t: 100), (x: 3.0, y: 4.0, t: 110)],
      ],
      language: 'en-US',
      preContext: 'the total linear momentum is',
      area: const Size(300, 40),
    );
    expect(read, ['momentum', 'momenta']);
    expect(calls[0].arguments, {'language': 'en-US'});
    expect(calls[1].arguments, {'language': 'en-US'});
    expect(calls[2].arguments, {
      'language': 'en-US',
      // Each stroke flat: x, y, t, x, y, t…
      'strokes': [
        [1.0, 2.0, 100, 3.0, 4.0, 110],
      ],
      // The last 20 characters of what came before.
      'preContext': 'l linear momentum is',
      'width': 300.0,
      'height': 40.0,
    });
  });

  test('a failure on the Android side is no model, or a reading that says why', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'recognize') throw PlatformException(code: 'recognize', message: 'No handwriting model for xx');
      return false;
    });
    final r = MlKitInkRecognizer();
    expect(await r.hasModel('en-US'), isFalse);
    expect(await r.downloadModel('en-US'), isFalse);
    await expectLater(r.recognize(const [], language: 'xx'), throwsA(isA<RecognitionFailed>()));
  });

  test('no Android side at all (an old build) is no model, never a hang', () async {
    final r = MlKitInkRecognizer(channel: const MethodChannel('nothing_listens_here'));
    expect(await r.hasModel('en-US'), isFalse);
    expect(await r.downloadModel('en-US'), isFalse);
    await expectLater(r.recognize(const [], language: 'en-US'), throwsA(isA<RecognitionFailed>()));
  });

  testWidgets('a call that never answers gives up after its time limit', (tester) async {
    final never = Completer<ByteData?>();
    messenger.setMockMessageHandler(MlKitInkRecognizer.channelName, (_) => never.future);
    addTearDown(() => messenger.setMockMessageHandler(MlKitInkRecognizer.channelName, null));
    final r = MlKitInkRecognizer();
    bool? has;
    Object? error;
    r.hasModel('en-US').then((v) => has = v);
    r.recognize(const [], language: 'en-US').catchError((Object e) {
      error = e;
      return <String>[];
    });
    await tester.pump(MlKitInkRecognizer.checkLimit + const Duration(seconds: 1));
    expect(has, isFalse);
    await tester.pump(MlKitInkRecognizer.readLimit);
    expect(error, isA<RecognitionFailed>());
  });
}
