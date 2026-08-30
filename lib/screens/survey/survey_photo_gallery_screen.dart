import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/survey_photo.dart';
import '../../services/reference_data_service.dart';
import '../../services/survey_data_provider.dart';
import '../../theme/app_theme.dart';

/// "Photos" gallery for a module ('BIODIVERSITE' | 'SOCIAL'): aggregates
/// every photo captured across ALL forms/records of the module (top-level
/// `image` fields AND photos nested inside repeat sections, e.g. "Photo
/// espèce"/"Photo habitat" inside "Identification espèce"), so field teams
/// and reviewers can browse everything captured without opening every
/// individual fiche.
///
/// Tapping a photo opens it full-screen with an option to save it to the
/// device via the system "Enregistrer sous" (save-as) picker
/// (file_picker's [FilePicker.saveFile], which accepts in-memory bytes on
/// Android — no separate storage permission required since Android 10+'s
/// Storage Access Framework handles the write).
class SurveyPhotoGalleryScreen extends StatelessWidget {
  final String module; // 'BIODIVERSITE' | 'SOCIAL'
  final String moduleTitle;

  const SurveyPhotoGalleryScreen({
    super.key,
    required this.module,
    required this.moduleTitle,
  });

  List<SurveyPhoto> _collectPhotos(SurveyDataProvider provider) {
    final schemas = ReferenceDataService.instance.surveySchemasForModule(
      module,
    );
    final photos = <SurveyPhoto>[];
    for (final schema in schemas) {
      final imageFields = schema.imageFields;
      if (imageFields.isEmpty) continue;
      final records = provider.recordsFor(schema.key);
      for (final record in records) {
        for (final ref in imageFields) {
          if (!ref.isInRepeat) {
            final data = record.values[ref.fieldName]?.toString();
            if (data != null && data.isNotEmpty) {
              photos.add(
                SurveyPhoto(
                  base64Data: data,
                  formKey: schema.key,
                  formTitle: schema.title,
                  recordId: record.id,
                  fieldLabel: ref.fieldLabel,
                  updatedAt: record.updatedAt,
                ),
              );
            }
          } else {
            final instances = record.repeats[ref.repeatName!] ?? const [];
            for (var i = 0; i < instances.length; i++) {
              final data = instances[i][ref.fieldName]?.toString();
              if (data != null && data.isNotEmpty) {
                photos.add(
                  SurveyPhoto(
                    base64Data: data,
                    formKey: schema.key,
                    formTitle: schema.title,
                    recordId: record.id,
                    fieldLabel: ref.fieldLabel,
                    repeatLabel: ref.repeatLabel,
                    repeatIndex: i,
                    updatedAt: record.updatedAt,
                  ),
                );
              }
            }
          }
        }
      }
    }
    photos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return photos;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SurveyDataProvider>();
    final photos = _collectPhotos(provider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Photos — $moduleTitle'),
      ),
      body: photos.isEmpty
          ? const _EmptyGallery()
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: photos.length,
              itemBuilder: (context, i) {
                final photo = photos[i];
                Uint8List? bytes;
                try {
                  bytes = base64Decode(photo.base64Data);
                } catch (_) {
                  bytes = null;
                }
                if (bytes == null) return const SizedBox.shrink();
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SurveyPhotoViewerScreen(photo: photo),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(bytes, fit: BoxFit.cover),
                  ),
                );
              },
            ),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 56,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'Aucune photo enregistrée pour le moment.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

/// Full-screen viewer for a single [SurveyPhoto], with a "Enregistrer sous"
/// (save-as) action that lets the user pick where to save the photo on
/// their device.
class SurveyPhotoViewerScreen extends StatefulWidget {
  final SurveyPhoto photo;
  const SurveyPhotoViewerScreen({super.key, required this.photo});

  @override
  State<SurveyPhotoViewerScreen> createState() =>
      _SurveyPhotoViewerScreenState();
}

class _SurveyPhotoViewerScreenState extends State<SurveyPhotoViewerScreen> {
  bool _saving = false;

  Future<void> _saveAs() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le téléchargement "enregistrer sous" est disponible sur '
            'l\'application Android, pas dans l\'aperçu Web.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final bytes = base64Decode(widget.photo.base64Data);
      final path = await FilePicker.saveFile(
        dialogTitle: 'Enregistrer la photo sous...',
        fileName: widget.photo.suggestedFileName(),
        type: FileType.image,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo enregistrée : $path'),
            backgroundColor: OkapiColors.secondary,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Échec de l\'enregistrement : $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    try {
      bytes = base64Decode(widget.photo.base64Data);
    } catch (_) {
      bytes = null;
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.photo.caption,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          IconButton(
            tooltip: 'Enregistrer sous...',
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_alt_rounded),
            onPressed: _saving ? null : _saveAs,
          ),
        ],
      ),
      body: Center(
        child: bytes != null
            ? InteractiveViewer(
                child: Image.memory(bytes, fit: BoxFit.contain),
              )
            : const Text(
                'Impossible d\'afficher cette photo.',
                style: TextStyle(color: Colors.white),
              ),
      ),
    );
  }
}
