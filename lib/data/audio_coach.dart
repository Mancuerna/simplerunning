import 'package:flutter/services.dart';

class AudioCoach {
  static const _channel = MethodChannel('simplerunning/coach');
  Future<void> cue(
    String text, {
    bool voice = true,
    bool haptics = true,
    bool countdown = false,
  }) async {
    if (haptics) {
      try {
        await HapticFeedback.mediumImpact();
      } on PlatformException {
        /* Continue with voice if vibration fails. */
      } on MissingPluginException {
        /* Tests. */
      }
    }
    try {
      if (voice) {
        await _channel.invokeMethod<void>('speak', text);
      } else {
        await _channel.invokeMethod<void>(
          'beep',
          countdown ? 'countdown' : 'transition',
        );
      }
    } on PlatformException {
      /* Unavailable speech must not interrupt the workout. */
    } on MissingPluginException {
      /* Tests and non-Android preview. */
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      /* Audio must never interrupt saving. */
    } on MissingPluginException {
      /* Tests. */
    }
  }
}
