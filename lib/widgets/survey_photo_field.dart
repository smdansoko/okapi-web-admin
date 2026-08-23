import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';

/// Reusable photo capture field for `image`-type SurveyNodes, following the
/// exact camera/gallery + base64 storage pattern used in
/// menage_form_screen.dart's `_pickPhotoBase64` / `_photoPickerBox`.
class SurveyPhotoField extends StatefulWidget {
  final String label;
  final String? base64Data;
  final ValueChanged<String?> onChanged;
  final bool required;

  const SurveyPhotoField({
    super.key,
    required this.label,
    required this.base64Data,
    required this.onChanged,
    this.required = false,
  });

  @override
  State<SurveyPhotoField> createState() => _SurveyPhotoFieldState();
}

class _SurveyPhotoFieldState extends State<SurveyPhotoField> {
  Future<String?> _pickPhotoBase64() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.of(c).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.of(c).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    try {
      final XFile? file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (file == null) return null;
      final Uint8List bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de capturer la photo : $e')),
        );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    if (widget.base64Data != null && widget.base64Data!.isNotEmpty) {
      try {
        bytes = base64Decode(widget.base64Data!);
      } catch (_) {
        bytes = null;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.required ? '${widget.label} *' : widget.label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final result = await _pickPhotoBase64();
            if (result != null) widget.onChanged(result);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.shade100,
            ),
            child: bytes != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(bytes, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: InkWell(
                          onTap: () => widget.onChanged(null),
                          child: const CircleAvatar(
                            radius: 12,
                            backgroundColor: OkapiColors.error,
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : const Icon(
                    Icons.add_a_photo_outlined,
                    color: Colors.grey,
                    size: 32,
                  ),
          ),
        ),
      ],
    );
  }
}
