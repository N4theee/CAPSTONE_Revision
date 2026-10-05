import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<void> downloadAdminCsv(String name, String content) async {
  final blob = web.Blob(
    ['\uFEFF$content'.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  anchor.click();
  await Future<void>.delayed(const Duration(seconds: 1));
  web.URL.revokeObjectURL(url);
}
