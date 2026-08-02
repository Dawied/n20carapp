import 'dart:js_interop';
import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;

Future<String> downloadArduinoCode() async {
  try {
    final String content = await rootBundle.loadString(
      'firmware/N20Car/N20Car.ino',
    );
    final blob = web.Blob(
      [content.toJS].toJS,
      web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = 'N20Car.ino';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return 'Downloaded N20Car.ino to your Downloads directory';
  } catch (e) {
    return 'Failed to download N20Car.ino: $e';
  }
}
