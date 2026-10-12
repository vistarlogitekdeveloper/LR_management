import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../utils/pod_photo.dart';

/// A POD ready to upload: from the camera or a chosen file.
class PodFile {
  final String name;
  final int size;

  /// Always set for a photo; for a chosen file when the platform read it.
  final Uint8List? bytes;

  /// A chosen file's path when its bytes were not read (native only).
  final String? path;

  const PodFile({
    required this.name,
    required this.size,
    this.bytes,
    this.path,
  });

  bool get isImage => !name.toLowerCase().endsWith('.pdf');
}

/// Take a photo of the POD (phones / tablets) or choose a photo / PDF, with a
/// preview of a photo so a blurred or cut-off POD is caught before it is sent.
class PodPicker extends StatefulWidget {
  final String lrNumber;
  final PodFile? file;
  final bool enabled;

  /// A POD that passed the checks, or null with the reason in [onError].
  final ValueChanged<PodFile?> onPicked;
  final ValueChanged<String?> onError;

  /// For tests: whether to offer the camera (defaults to phones / tablets).
  final bool? cameraAvailable;

  /// For tests: the camera.
  final ImagePicker? imagePicker;

  const PodPicker({
    super.key,
    required this.lrNumber,
    required this.file,
    required this.enabled,
    required this.onPicked,
    required this.onError,
    this.cameraAvailable,
    this.imagePicker,
  });

  @override
  State<PodPicker> createState() => _PodPickerState();
}

class _PodPickerState extends State<PodPicker> {
  bool _busy = false;

  void _accept(PodFile f) {
    final error = podFileError(f.name, f.size);
    widget.onError(error);
    widget.onPicked(error == null ? f : null);
  }

  Future<void> _choose() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: podExtensions,
      // Web has no file path, so the bytes are needed to upload.
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    _accept(PodFile(name: f.name, size: f.size, bytes: f.bytes, path: f.path));
  }

  Future<void> _takePhoto() async {
    setState(() => _busy = true);
    try {
      final shot = await (widget.imagePicker ?? ImagePicker()).pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        // Sharp enough to read every line of a POD, small enough to upload
        // over a weak connection (a raw phone photo is 4–12 MB).
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 85,
      );
      if (shot == null) return; // the camera was closed without a photo
      final bytes = await shot.readAsBytes();
      final name = podPhotoName(
        widget.lrNumber,
        DateTime.now(),
        mimeType: shot.mimeType,
      );
      _accept(PodFile(name: name, size: bytes.length, bytes: bytes));
    } on PlatformException catch (e) {
      widget.onError(
        e.code.contains('access_denied') || e.code.contains('camera_access')
            ? 'The camera is not allowed for this app. Allow it in the phone settings, or choose a photo / PDF.'
            : 'The camera could not be opened. Choose a photo / PDF instead.',
      );
    } catch (_) {
      widget.onError(
        'The camera could not be opened. Choose a photo / PDF instead.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    final camera = widget.cameraAvailable ?? canTakePodPhoto();
    final enabled = widget.enabled && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (camera)
              AppButton(
                label: f == null ? 'Take photo' : 'Retake photo',
                icon: Icons.photo_camera_outlined,
                small: true,
                loading: _busy,
                onPressed: enabled ? _takePhoto : null,
              ),
            AppButton(
              label: f == null ? 'Choose photo / PDF' : 'Change file',
              icon: Icons.upload_file_rounded,
              kind: BtnKind.soft,
              small: true,
              onPressed: enabled ? _choose : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          f == null
              ? 'No file chosen'
              : '${f.name} · ${(f.size / 1024).ceil()} KB',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            color: f == null ? AppColors.slate : AppColors.ink,
            fontWeight: f == null ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
        if (f != null && f.isImage && f.bytes != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 180),
              width: double.infinity,
              color: AppColors.inputBg,
              child: Image.memory(
                f.bytes!,
                fit: BoxFit.contain,
                // A HEIC the browser cannot draw is still a valid upload.
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Preview not available for this photo.',
                    style: TextStyle(fontSize: 12, color: AppColors.slate),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Check that the POD is clear and complete before sending.',
            style: TextStyle(fontSize: 11.5, color: AppColors.slate),
          ),
        ],
      ],
    );
  }
}
