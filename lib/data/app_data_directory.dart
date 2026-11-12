import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<Directory> pulseAppDataDirectory() async {
  if (Platform.isWindows) {
    final base =
        Platform.environment['LOCALAPPDATA'] ?? Platform.environment['APPDATA'];
    if (base == null || base.isEmpty) {
      throw const FileSystemException(
          'A pasta de dados local do Pulse não está disponível.');
    }
    final directory = Directory('$base${Platform.pathSeparator}PulseFlutter');
    await directory.create(recursive: true);
    return directory;
  }

  final support = await getApplicationSupportDirectory();
  final directory =
      Directory('${support.path}${Platform.pathSeparator}PulseFlutter');
  await directory.create(recursive: true);
  return directory;
}
