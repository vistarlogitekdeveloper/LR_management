import 'package:flutter/foundation.dart';

/// What may be picked as a POD — a photo or a scanned PDF. Matches the
/// server's POD check (services/balanceRequest.service.js).
const podExtensions = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'pdf'];

/// The server's upload limit (middleware/upload.js), checked here so a large
/// photo is refused before it is sent rather than after.
const podMaxBytes = 25 * 1024 * 1024;

/// Null when [fileName] / [size] is an acceptable POD, else the message.
String? podFileError(String fileName, int size) {
  final ext = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : '';
  if (!podExtensions.contains(ext)) {
    return 'The POD must be a photo (JPG, PNG, HEIC) or a PDF.';
  }
  if (size <= 0) return 'That file is empty. Choose the POD again.';
  if (size > podMaxBytes) return 'The POD must be smaller than 25 MB.';
  return null;
}

/// Whether the POD can be photographed here: a phone or tablet, native or in
/// its browser. On a desktop browser the camera option would only open the
/// file chooser again, so it is not offered there.
bool canTakePodPhoto({TargetPlatform? platform}) {
  final p = platform ?? defaultTargetPlatform;
  return p == TargetPlatform.android || p == TargetPlatform.iOS;
}

/// The file name a POD photo is uploaded under —
/// "POD-LR-PUN-26-27-00012-20261012-1430.jpg" — so Accounts can tell whose
/// POD it is, whatever the phone called it ("image.jpg", a blob id...).
String podPhotoName(String lrNumber, DateTime at, {String? mimeType}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final lr = lrNumber
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  final stamp =
      '${at.year}${two(at.month)}${two(at.day)}-${two(at.hour)}${two(at.minute)}';
  return 'POD-${lr.isEmpty ? 'LR' : lr}-$stamp.${podPhotoExtension(mimeType)}';
}

/// The extension for a photo's mime type; JPEG (what cameras and the resize
/// produce) when unknown.
String podPhotoExtension(String? mimeType) =>
    switch ((mimeType ?? '').toLowerCase()) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      _ => 'jpg',
    };
