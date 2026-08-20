import 'package:flutter/material.dart';
import '../screens/sync/sync_screen.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Small self-contained banner showing the last successful synchronization
/// time with the OKAPI Web Admin server. Tapping it opens the "Synchroniser"
/// screen. Used on the "Enquête Ménages" and "Contrats" screens so the
/// sync status/updates are visible right where the data is used.
class SyncStatusBanner extends StatefulWidget {
  const SyncStatusBanner({super.key});

  @override
  State<SyncStatusBanner> createState() => _SyncStatusBannerState();
}

class _SyncStatusBannerState extends State<SyncStatusBanner> {
  DateTime? _lastSyncAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final last = await SyncService.instance.lastSyncAt;
    if (mounted) setState(() => _lastSyncAt = last);
  }

  Future<void> _openSync() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SyncScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _openSync,
      child: Container(
        width: double.infinity,
        color: OkapiColors.secondary.withValues(alpha: 0.07),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.cloud_done_outlined,
              size: 16,
              color: OkapiColors.secondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _lastSyncAt != null
                    ? 'Dernière synchronisation : ${Formatters.date(_lastSyncAt!)} à '
                          '${_lastSyncAt!.hour.toString().padLeft(2, '0')}:'
                          '${_lastSyncAt!.minute.toString().padLeft(2, '0')}'
                    : 'Données non synchronisées avec le serveur OKAPI Web Admin.',
                style: TextStyle(
                  fontSize: 12,
                  color: OkapiColors.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: OkapiColors.secondary,
            ),
          ],
        ),
      ),
    );
  }
}
