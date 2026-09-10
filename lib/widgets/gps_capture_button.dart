import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_theme.dart';

/// Maximum GPS accuracy (in meters) accepted by "Enregistrer le point GPS".
/// A reading whose reported accuracy is worse (larger) than this value is
/// rejected and the user is prompted to try again (e.g. move to open sky,
/// wait a few seconds for the GPS fix to refine).
const double kGpsMaxAccuracyMeters = 5.0;

/// Result of a successful GPS capture.
class GpsPoint {
  final double latitude;
  final double longitude;
  final double accuracy;

  const GpsPoint({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });
}

/// Requests location permission (if needed) and returns the current GPS
/// position, retrying for up to ~12 seconds to obtain a reading with
/// accuracy <= [kGpsMaxAccuracyMeters]. Returns null (with a SnackBar
/// explanation) if permission is denied, location services are disabled,
/// or no sufficiently accurate fix could be obtained in time.
Future<GpsPoint?> captureGpsPoint(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);

  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Veuillez activer la localisation (GPS) de l\'appareil.',
        ),
      ),
    );
    return null;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Permission de localisation refusée. Impossible de prendre le point GPS.',
        ),
      ),
    );
    return null;
  }

  // Show a small "Recherche du signal GPS..." dialog while we wait for a
  // sufficiently precise fix (<= 5 m), so the user gets feedback instead of
  // a frozen-looking button.
  bool dialogOpen = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Recherche du signal GPS (précision ≤ 5 m)...',
              ),
            ),
          ],
        ),
      ),
    ).then((_) => dialogOpen = false),
  );

  GpsPoint? best;
  try {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 5),
          ),
        );
        final candidate = GpsPoint(
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
        );
        if (best == null || candidate.accuracy < best.accuracy) {
          best = candidate;
        }
        if (candidate.accuracy <= kGpsMaxAccuracyMeters) {
          best = candidate;
          break;
        }
      } catch (_) {
        // Ignore transient errors (e.g. timeout on a single attempt) and
        // retry until the deadline.
      }
    }
  } finally {
    if (dialogOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  if (best == null) {
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d\'obtenir la position GPS. Veuillez réessayer en extérieur.',
          ),
        ),
      );
    }
    return null;
  }

  if (best.accuracy > kGpsMaxAccuracyMeters) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Précision insuffisante (${best.accuracy.toStringAsFixed(1)} m > '
            '${kGpsMaxAccuracyMeters.toStringAsFixed(0)} m). Veuillez réessayer.',
          ),
        ),
      );
    }
    return null;
  }

  return best;
}

/// A small "Enregistrer le point GPS" button + status caption, used next to
/// latitude/longitude fields throughout the survey forms. On tap, captures
/// the device's current GPS position (retrying until accuracy <= 5 m, up to
/// ~12 seconds) and reports it via [onCaptured].
class GpsCaptureButton extends StatefulWidget {
  final ValueChanged<GpsPoint> onCaptured;
  final double? lastAccuracy;

  const GpsCaptureButton({
    super.key,
    required this.onCaptured,
    this.lastAccuracy,
  });

  @override
  State<GpsCaptureButton> createState() => _GpsCaptureButtonState();
}

class _GpsCaptureButtonState extends State<GpsCaptureButton> {
  bool _busy = false;

  Future<void> _capture() async {
    setState(() => _busy = true);
    final point = await captureGpsPoint(context);
    if (!mounted) return;
    setState(() => _busy = false);
    if (point != null) {
      widget.onCaptured(point);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Point GPS enregistré (précision ${point.accuracy.toStringAsFixed(1)} m).',
            ),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _capture,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location_rounded, size: 18),
          label: Text(
            _busy ? 'Recherche GPS...' : 'Enregistrer le point GPS',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: OkapiColors.primary,
            side: const BorderSide(color: OkapiColors.primary),
          ),
        ),
        if (widget.lastAccuracy != null) ...[
          const SizedBox(height: 4),
          Text(
            'Précision de la dernière prise : '
            '${widget.lastAccuracy!.toStringAsFixed(1)} m',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }
}
