import 'dart:convert';
import 'dart:io';

class AppPreferences {
  AppPreferences(this.file) {
    if (file != null && file!.existsSync()) {
      try {
        final decoded = jsonDecode(file!.readAsStringSync());
        if (decoded is Map<String, dynamic>) values = decoded;
      } on FormatException {
        values = {};
      }
    }
  }
  final File? file;
  Map<String, dynamic> values = {};
  bool get voice => values['voice'] != false;
  bool get haptics => values['haptics'] != false;
  String? get treadmillId {
    final device = values['treadmill'];
    if (device is! Map) return null;
    final id = device['id'];
    return id is String && id.trim().isNotEmpty ? id : null;
  }

  String get treadmillName {
    final device = values['treadmill'];
    final name = device is Map ? device['name'] : null;
    return name is String && name.trim().isNotEmpty ? name : 'Tu cinta';
  }

  int number(String key, int fallback) {
    final value = values[key];
    return value is num && value.isFinite ? value.toInt() : fallback;
  }

  void set(String key, Object? value) {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    final target = file;
    if (target == null) return;
    target.parent.createSync(recursive: true);
    final temp = File('${target.path}.tmp');
    temp.writeAsStringSync(jsonEncode(values), flush: true);
    temp.renameSync(target.path);
  }
}
