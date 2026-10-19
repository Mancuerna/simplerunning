import 'package:flutter/services.dart';

class FileExchange {
  static const _channel = MethodChannel('simplerunning/coach');
  Future<String?> pickBackup() => _channel.invokeMethod<String>('pickBackup');
}
