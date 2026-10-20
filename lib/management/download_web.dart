// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Web build: trigger a browser download for [bytes].
///
/// Returns true — the browser handles the file itself.
bool downloadFile(List<int> bytes, String fileName) {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  // Revoking the object URL immediately can cancel the download in some
  // browsers; it is released when the document goes away instead.
  return true;
}
