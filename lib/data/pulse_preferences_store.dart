import 'dart:convert';
import 'dart:io';

import '../domain/pulse_preferences.dart';
import 'app_data_directory.dart';

class PulsePreferencesStore {
  PulsePreferencesStore({Directory? storageDirectory})
      : _directory = storageDirectory;
  final Directory? _directory;
  Future<void> _writes = Future<void>.value();

  Future<PulsePreferences> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const PulsePreferences();
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic>
          ? PulsePreferences.fromJson(decoded)
          : const PulsePreferences();
    } on Object {
      return const PulsePreferences();
    }
  }

  Future<void> save(PulsePreferences preferences) {
    final next = _writes.then((_) => _save(preferences));
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _save(PulsePreferences preferences) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(preferences.toJson()),
        flush: true);
    await temporary.rename(file.path);
  }

  Future<File> _file() async {
    final directory = _directory ?? await pulseAppDataDirectory();
    return File('${directory.path}${Platform.pathSeparator}preferences.json');
  }
}
