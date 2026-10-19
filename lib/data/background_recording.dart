import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class BackgroundRecording {
  static const _channel = MethodChannel('simplerunning/recording');

  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) {
      await WakelockPlus.toggle(enable: enabled);
      return;
    }
    if (enabled) {
      // Android allows the service even if notification permission is denied.
      await Permission.notification.request();
    }
    await _channel.invokeMethod<void>(enabled ? 'start' : 'stop');
  }
}
