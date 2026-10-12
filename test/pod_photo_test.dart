// "Take photo" for the POD (2026-10-12): on a phone or tablet the POD of a
// balance request can be photographed instead of picked as a file. The
// naming and platform rules, and the picker with a fake camera: a photo, the
// camera closed without one, no camera permission, a photo too large, and no
// camera offered on a desktop.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:lr_management/features/lr/utils/pod_photo.dart';
import 'package:lr_management/features/lr/widgets/pod_picker.dart';

// A 1×1 PNG, so the preview really decodes.
final _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0xF0,
  0x1F,
  0x00,
  0x05,
  0x00,
  0x01,
  0xFF,
  0x89,
  0x99,
  0x3D,
  0x1D,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  group('rules', () {
    test('the camera is offered on phones and tablets only', () {
      expect(canTakePodPhoto(platform: TargetPlatform.android), isTrue);
      expect(canTakePodPhoto(platform: TargetPlatform.iOS), isTrue);
      for (final p in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(canTakePodPhoto(platform: p), isFalse, reason: '$p');
      }
    });

    test(
      'a photo is named after the LR and the moment, whatever the phone called it',
      () {
        final at = DateTime(2026, 10, 12, 14, 5);
        expect(
          podPhotoName('LR/PUN/26-27/00012', at),
          'POD-LR-PUN-26-27-00012-20261012-1405.jpg',
        );
        expect(
          podPhotoName('LR/Manual/PUN/0001', at, mimeType: 'image/png'),
          'POD-LR-Manual-PUN-0001-20261012-1405.png',
        );
        expect(podPhotoName('', at), 'POD-LR-20261012-1405.jpg');
        expect(podPhotoExtension('IMAGE/HEIC'), 'heic');
        expect(podPhotoExtension(null), 'jpg');
      },
    );

    test('every photo name passes the POD check', () {
      for (final m in [
        null,
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/heic',
        'image/heif',
      ]) {
        expect(
          podFileError(podPhotoName('LR/1', DateTime(2026), mimeType: m), 1000),
          isNull,
          reason: '$m',
        );
      }
    });
  });

  group('the picker', () {
    testWidgets('takes a photo: renamed after the LR, previewed, handed over', (
      tester,
    ) async {
      final cam = _Camera(
        () async =>
            XFile.fromData(_png, name: 'image.jpg', mimeType: 'image/png'),
      );
      final h = await _pump(tester, cam);
      expect(find.text('Take photo'), findsOneWidget);
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();
      expect(cam.calls, 1);
      expect(cam.lastSource, ImageSource.camera);
      expect(
        cam.lastQuality,
        85,
        reason: 'resized to upload over a weak connection',
      );
      expect(h.picked.last?.name, startsWith('POD-LR-PUN-26-27-00012-'));
      expect(h.picked.last?.name, endsWith('.png'));
      expect(h.picked.last?.bytes, _png);
      expect(h.errors.last, isNull);
      // The parent re-renders with the photo: preview and "Retake".
      await _pump(tester, cam, file: h.picked.last, harness: h);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Retake photo'), findsOneWidget);
      expect(find.textContaining('clear and complete'), findsOneWidget);
    });

    testWidgets('the camera closed without a photo changes nothing', (
      tester,
    ) async {
      final h = await _pump(tester, _Camera(() async => null));
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();
      expect(h.picked, isEmpty);
      expect(h.errors, isEmpty);
    });

    testWidgets(
      'no camera permission: says how to fix it, offers the file instead',
      (tester) async {
        final h = await _pump(
          tester,
          _Camera(
            () async => throw PlatformException(code: 'camera_access_denied'),
          ),
        );
        await tester.tap(find.text('Take photo'));
        await tester.pumpAndSettle();
        expect(h.errors.last, contains('Allow it in the phone settings'));
        expect(h.picked, isEmpty);
        expect(find.text('Choose photo / PDF'), findsOneWidget);
      },
    );

    testWidgets('any other camera failure is said plainly', (tester) async {
      final h = await _pump(
        tester,
        _Camera(() async => throw StateError('no camera')),
      );
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();
      expect(h.errors.last, contains('could not be opened'));
    });

    testWidgets('a photo over 25 MB is refused before it is sent', (
      tester,
    ) async {
      final big = Uint8List(26 * 1024 * 1024);
      final h = await _pump(
        tester,
        _Camera(() async => XFile.fromData(big, mimeType: 'image/jpeg')),
      );
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();
      expect(h.errors.last, contains('25 MB'));
      expect(h.picked.last, isNull);
    });

    testWidgets('a desktop browser gets the file chooser only', (tester) async {
      await _pump(tester, _Camera(() async => null), camera: false);
      expect(find.text('Take photo'), findsNothing);
      expect(find.text('Choose photo / PDF'), findsOneWidget);
    });

    testWidgets('a chosen PDF shows its name, no preview', (tester) async {
      final h = _Harness();
      await _pump(
        tester,
        _Camera(() async => null),
        file: PodFile(name: 'pod.pdf', size: 2048, bytes: Uint8List(2048)),
        harness: h,
      );
      expect(find.text('pod.pdf · 2 KB'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('while sending, nothing can be picked', (tester) async {
      final cam = _Camera(() async => null);
      await _pump(tester, cam, enabled: false);
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();
      expect(cam.calls, 0);
    });
  });
}

class _Harness {
  final picked = <PodFile?>[];
  final errors = <String?>[];
}

Future<_Harness> _pump(
  WidgetTester tester,
  _Camera cam, {
  bool camera = true,
  bool enabled = true,
  PodFile? file,
  _Harness? harness,
}) async {
  final h = harness ?? _Harness();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 440,
          child: PodPicker(
            lrNumber: 'LR/PUN/26-27/00012',
            file: file,
            enabled: enabled,
            onPicked: h.picked.add,
            onError: h.errors.add,
            cameraAvailable: camera,
            imagePicker: cam,
          ),
        ),
      ),
    ),
  );
  return h;
}

class _Camera implements ImagePicker {
  _Camera(this._next);
  final Future<XFile?> Function() _next;
  int calls = 0;
  ImageSource? lastSource;
  int? lastQuality;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) {
    calls += 1;
    lastSource = source;
    lastQuality = imageQuality;
    return _next();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
