import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'file_downloader_web.dart'
    if (dart.library.io) 'file_downloader.dart' as impl;

Future<String> saveArduinoCodeToDownloads() => impl.downloadArduinoCode();

Future<String> downloadArduinoCode() async {
  try {
    final String content = await rootBundle.loadString(
      'firmware/N20Car/N20Car.ino',
    );
    Directory? directory;
    try {
      directory = await getDownloadsDirectory();
    } catch (_) {
      directory = null;
    }
    if (directory == null) {
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getApplicationDocumentsDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
    }
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final String filePath = '${directory.path}/N20Car.ino';
    final File file = File(filePath);
    await file.writeAsString(content);
    return 'Saved N20Car.ino to ${directory.path}';
  } catch (e) {
    return 'Failed to save N20Car.ino: $e';
  }
}
