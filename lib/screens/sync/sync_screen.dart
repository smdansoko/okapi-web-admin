import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/menage.dart';
import '../../models/enquete_champ.dart';
import '../../models/structure.dart';
import '../../main.dart' show kAllSurveyFormKeys;
import '../../services/app_data_provider.dart';
import '../../services/auth_service.dart';
import '../../services/photo_cache_service.dart';
import '../../services/session_service.dart';
import '../../services/survey_data_provider.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// Only users with one of these exact "statut" values are allowed to push
/// data to the server via "Synchroniser" (PUSH). All users (regardless of
/// statut) may still pull via "Actualiser". "Chef d'équipe" pushes the
/// PARC team's ménages/champs/structures; "Expert Biodiversité"/"Expert
/// Social" push their own module's survey records (there is no separate
/// "chef" role for those modules).
const String _kChefDEquipeStatut = "Chef d'équipe";
const Set<String> _kAllowedPushStatuts = {
  _kChefDEquipeStatut,
  SessionService.kExpertBiodiversite,
  SessionService.kExpertSocial,
};

/// "Synchroniser" tab: lets the field team push all locally collected data
/// (Ménages, Enquêtes Champs, Enquêtes Structures — including the recent
/// updates: member photos/CNI, numéro de lot from numBatch, etc.) to the
/// separate OKAPI Web Admin server, where it becomes available for
/// contract PDF export and compensation table (Excel) export.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _urlController = TextEditingController();
  final _deviceNameController = TextEditingController();

  bool _loadingPrefs = true;
  bool _syncing = false;
  bool _pulling = false;
  bool _testingConnection = false;
  bool? _connectionOk;
  DateTime? _lastSyncAt;
  SyncResult? _lastResult;
  PullResult? _lastPullResult;

  // ---- Legacy photo download (offline cache) state ----
  bool _downloadingPhotos = false;
  int _photosDone = 0;
  int _photosTotal = 0;
  String? _photosResultMessage;
  bool? _photosResultOk;

  AppUser? _currentUser;
  bool get _canSynchronize =>
      _currentUser != null && _kAllowedPushStatuts.contains(_currentUser!.statut);

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final user = await AuthService.instance.currentUser;
    if (!mounted) return;
    setState(() => _currentUser = user);
  }

  Future<void> _loadPrefs() async {
    final url = await SyncService.instance.serverUrl;
    final name = await SyncService.instance.deviceName;
    final last = await SyncService.instance.lastSyncAt;
    if (!mounted) return;
    setState(() {
      _urlController.text = url;
      _deviceNameController.text = name;
      _lastSyncAt = last;
      _loadingPrefs = false;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _saveServerSettings() async {
    await SyncService.instance.setServerUrl(_urlController.text);
    await SyncService.instance.setDeviceName(_deviceNameController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paramètres de synchronisation enregistrés.'),
        ),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _connectionOk = null;
    });
    final ok = await SyncService.instance.testConnection(_urlController.text);
    if (!mounted) return;
    setState(() {
      _testingConnection = false;
      _connectionOk = ok;
    });
  }

  /// Restricts the data about to be pushed to the server to ONLY the
  /// records that belong to the current "Chef d'équipe" account's own
  /// tablette (device/tablet number), per the "chef ne synchronise que sa
  /// tablette" requirement. Each Menage/EnqueteChamp/EnqueteStructure
  /// record carries its own `tablette` field (filled in via the
  /// "Tablette" dropdown on the survey forms). If the logged-in chef has
  /// no tablette assigned to their account (older accounts created before
  /// this field existed), sync is not restricted (backward compatibility)
  /// but a warning is shown so the issue can be corrected.
  ({
    List<Menage> menages,
    List<EnqueteChamp> champs,
    List<EnqueteStructure> structures,
  })
  _dataForSync(AppDataProvider data) {
    final myTablette = _currentUser?.tablette ?? '';
    if (myTablette.isEmpty) {
      return (
        menages: data.menages,
        champs: data.champs,
        structures: data.structures,
      );
    }
    return (
      menages: data.menages.where((m) => m.tablette == myTablette).toList(),
      champs: data.champs.where((c) => c.tablette == myTablette).toList(),
      structures: data.structures
          .where((s) => s.tablette == myTablette)
          .toList(),
    );
  }

  Future<void> _synchronize() async {
    if (!_canSynchronize) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Seuls les utilisateurs avec le statut "$_kChefDEquipeStatut", '
            '"${SessionService.kExpertBiodiversite}" ou '
            '"${SessionService.kExpertSocial}" peuvent effectuer la '
            'synchronisation (envoi vers le serveur).',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    await _saveServerSettings();
    if (!mounted) return;
    final data = context.read<AppDataProvider>();
    final surveyData = context.read<SurveyDataProvider>();

    final myTablette = _currentUser?.tablette ?? '';
    if (myTablette.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Attention : aucune tablette n\'est associée à votre compte — '
            'toutes les données locales seront synchronisées (mode '
            'compatibilité). Recréez votre compte pour restreindre la '
            'synchronisation à votre tablette.',
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 5),
        ),
      );
    }
    final toSync = _dataForSync(data);
    final surveyRecordsToSync = {
      for (final key in kAllSurveyFormKeys) key: surveyData.recordsFor(key),
    };

    setState(() {
      _syncing = true;
      _lastResult = null;
    });

    final pendingDeletions = data.pendingDeletions;

    final result = await SyncService.instance.syncAll(
      menages: toSync.menages,
      champs: toSync.champs,
      structures: toSync.structures,
      surveyRecords: surveyRecordsToSync,
      deletions: pendingDeletions,
    );

    if (result.success && pendingDeletions.isNotEmpty) {
      await data.clearPendingDeletions(
        pendingDeletions.map(
          (d) => (
            recordType: d['recordType'] as String,
            recordId: d['recordId'] as String,
          ),
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _syncing = false;
      _lastResult = result;
      if (result.success) _lastSyncAt = DateTime.now();
    });

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Synchronisation réussie ✔'),
          backgroundColor: OkapiColors.secondary,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  /// "Actualiser" action: pulls ALL ménages/enquêtes currently stored on
  /// the OKAPI Web Admin server — including households registered on
  /// ANOTHER tablet and pushed there via their own "Synchroniser" action —
  /// and merges them into this device's local data, so they immediately
  /// appear in the Champs/Structures survey forms (ménage & propriétaire
  /// pickers).
  Future<void> _actualiser() async {
    await _saveServerSettings();
    if (!mounted) return;
    final data = context.read<AppDataProvider>();
    final surveyData = context.read<SurveyDataProvider>();

    setState(() {
      _pulling = true;
      _lastPullResult = null;
    });

    final result = await SyncService.instance.pullFromServer();

    if (result.success) {
      await data.mergeFromServer(
        menages: result.menages,
        champs: result.champs,
        structures: result.structures,
        deletions: result.deletions,
      );
      await surveyData.mergeFromServer(result.surveyRecords);
    }

    if (!mounted) return;
    setState(() {
      _pulling = false;
      _lastPullResult = result;
      if (result.success) _lastSyncAt = DateTime.now();
    });

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Actualisation réussie ✔ — Ménages: ${result.menages.length} · '
            'Champs: ${result.champs.length} · '
            'Structures: ${result.structures.length}',
          ),
          backgroundColor: OkapiColors.secondary,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  /// Downloads every legacy member photo (uploaded by the admin on the
  /// web) for the CURRENT project onto this device's local storage, so
  /// they remain available for display in generated contracts even
  /// without internet afterwards. Only downloads photos not already
  /// cached (incremental), so pressing this again after the first full
  /// download is fast.
  Future<void> _downloadPhotos() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le stockage local des photos hors-ligne n\'est disponible '
            'que sur l\'application Android, pas dans l\'aperçu Web.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    await _saveServerSettings();
    if (!mounted) return;
    setState(() {
      _downloadingPhotos = true;
      _photosDone = 0;
      _photosTotal = 0;
      _photosResultMessage = null;
      _photosResultOk = null;
    });
    try {
      final count = await PhotoCacheService.instance
          .downloadCurrentProjectPhotos(
            onProgress: (done, total) {
              if (!mounted) return;
              setState(() {
                _photosDone = done;
                _photosTotal = total;
              });
            },
          );
      if (!mounted) return;
      setState(() {
        _downloadingPhotos = false;
        _photosResultOk = true;
        _photosResultMessage = count > 0
            ? '$count nouvelle(s) photo(s) téléchargée(s) et disponible(s) hors-ligne.'
            : 'Toutes les photos disponibles sont déjà téléchargées sur cet appareil.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingPhotos = false;
        _photosResultOk = false;
        _photosResultMessage = 'Échec du téléchargement des photos : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppDataProvider>();
    final surveyData = context.watch<SurveyDataProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipOval(
              child: Image.asset(
                'assets/logo/okapi_icon_circular.png',
                height: 32,
                width: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Synchroniser', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: _loadingPrefs
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        ClipOval(
                          child: Image.asset(
                            'assets/logo/okapi_icon_circular.png',
                            height: 56,
                            width: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Text(
                            'Envoyez les données collectées sur le terrain vers le serveur '
                            'OKAPI Web Admin : contrats PDF et tableau d\'indemnisation '
                            'y sont générés automatiquement.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Données locales à synchroniser ----
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Données locales prêtes à synchroniser',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _CountChip(
                              icon: Icons.groups_rounded,
                              label: 'Ménages',
                              count: data.totalMenages,
                              color: OkapiColors.primary,
                            ),
                            _CountChip(
                              icon: Icons.person_rounded,
                              label: 'Individus',
                              count: data.totalIndividus,
                              color: OkapiColors.secondary,
                            ),
                            _CountChip(
                              icon: Icons.grass_rounded,
                              label: 'Enquêtes Champs',
                              count: data.champs.length,
                              color: const Color(0xFFC77B00),
                            ),
                            _CountChip(
                              icon: Icons.home_work_rounded,
                              label: 'Enquêtes Structures',
                              count: data.structures.length,
                              color: const Color(0xFF1F5A8F),
                            ),
                            _CountChip(
                              icon: Icons.eco_rounded,
                              label: 'Biodiversité',
                              count: surveyData.totalBiodiversiteRecords,
                              color: OkapiColors.secondary,
                            ),
                            _CountChip(
                              icon: Icons.people_alt_rounded,
                              label: 'Social',
                              count: surveyData.totalSocialRecords,
                              color: OkapiColors.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 16,
                              color: OkapiColors.textLight,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Inclut les photos (profil + CNI recto/verso), le numéro de lot '
                                '(N° de batch) et toutes les informations des contrats.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Configuration du serveur ----
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Serveur OKAPI Web Admin',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _urlController,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Adresse du serveur (URL)',
                            hintText: 'https://exemple.okapi-admin.com',
                            prefixIcon: Icon(Icons.link),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _deviceNameController,
                          decoration: const InputDecoration(
                            labelText: 'Nom de cet appareil (optionnel)',
                            hintText: 'ex: Tablette Enquêteur 1',
                            prefixIcon: Icon(Icons.tablet_android),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _testingConnection
                                  ? null
                                  : _testConnection,
                              icon: _testingConnection
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.wifi_tethering),
                              label: const Text('Tester la connexion'),
                            ),
                            const SizedBox(width: 12),
                            if (_connectionOk == true)
                              const Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: OkapiColors.secondary,
                                    size: 18,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Serveur accessible',
                                    style: TextStyle(
                                      color: OkapiColors.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            if (_connectionOk == false)
                              Row(
                                children: [
                                  Icon(
                                    Icons.error,
                                    color: Colors.red.shade700,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Serveur injoignable',
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _saveServerSettings,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('Enregistrer les paramètres'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Dernier statut de synchronisation ----
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Statut',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.history,
                              size: 18,
                              color: OkapiColors.textLight,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _lastSyncAt != null
                                  ? 'Dernière synchronisation réussie : '
                                        '${Formatters.date(_lastSyncAt!)} à '
                                        '${_lastSyncAt!.hour.toString().padLeft(2, '0')}:'
                                        '${_lastSyncAt!.minute.toString().padLeft(2, '0')}'
                                  : 'Aucune synchronisation effectuée pour le moment.',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                        if (_lastResult != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _lastResult!.success
                                  ? OkapiColors.secondary.withValues(
                                      alpha: 0.08,
                                    )
                                  : Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _lastResult!.success
                                    ? OkapiColors.secondary.withValues(
                                        alpha: 0.3,
                                      )
                                    : Colors.red.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _lastResult!.success
                                      ? 'Synchronisation réussie'
                                      : 'Échec de la synchronisation',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _lastResult!.success
                                        ? OkapiColors.secondary
                                        : Colors.red.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _lastResult!.message,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                                if (_lastResult!.received != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Envoyé — Ménages: ${_lastResult!.received!['menages'] ?? 0} · '
                                    'Champs: ${_lastResult!.received!['champs'] ?? 0} · '
                                    'Structures: ${_lastResult!.received!['structures'] ?? 0}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                                if (_lastResult!.serverTotals != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Total sur le serveur — Ménages: ${_lastResult!.serverTotals!['menages'] ?? 0} · '
                                    'Champs: ${_lastResult!.serverTotals!['champs'] ?? 0} · '
                                    'Structures: ${_lastResult!.serverTotals!['structures'] ?? 0}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_syncing || !_canSynchronize)
                        ? null
                        : _synchronize,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OkapiColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade400,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _canSynchronize
                                ? Icons.cloud_upload_rounded
                                : Icons.lock_outline,
                          ),
                    label: Text(
                      _syncing
                          ? 'Synchronisation en cours…'
                          : 'Synchroniser maintenant',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (!_canSynchronize) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.red.shade700,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Réservé aux utilisateurs avec le statut '
                          '"$_kChefDEquipeStatut". Votre statut actuel : '
                          '${_currentUser?.statut.isNotEmpty == true ? _currentUser!.statut : "inconnu"}.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_canSynchronize) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: OkapiColors.textLight,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          (_currentUser?.tablette.isNotEmpty == true)
                              ? 'Seules les données de votre tablette (Tablette '
                                    '${_currentUser!.tablette}) seront envoyées au serveur.'
                              : 'Aucune tablette associée à votre compte : toutes '
                                    'les données locales seront envoyées (non filtré).',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),

                // ---- Actualiser (pull-sync croisé entre tablettes) ----
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pulling ? null : _actualiser,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: OkapiColors.primary,
                      side: const BorderSide(color: OkapiColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _pulling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download_rounded),
                    label: Text(
                      _pulling ? 'Actualisation en cours…' : 'Actualiser',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: OkapiColors.textLight,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Récupère les ménages, enquêtes champs et structures enregistrés '
                        'sur les AUTRES tablettes et les rend immédiatement disponibles '
                        'ici (listes déroulantes Ménage / Propriétaire).',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_lastPullResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _lastPullResult!.success
                          ? OkapiColors.secondary.withValues(alpha: 0.08)
                          : Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _lastPullResult!.success
                            ? OkapiColors.secondary.withValues(alpha: 0.3)
                            : Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _lastPullResult!.success
                              ? 'Actualisation réussie'
                              : 'Échec de l\'actualisation',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _lastPullResult!.success
                                ? OkapiColors.secondary
                                : Colors.red.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _lastPullResult!.message,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        if (_lastPullResult!.success) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Reçu du serveur — Ménages: ${_lastPullResult!.menages.length} · '
                            'Champs: ${_lastPullResult!.champs.length} · '
                            'Structures: ${_lastPullResult!.structures.length}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // ---- Photos hors-ligne (téléchargement des photos web) ----
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Photos des membres (hors-ligne)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Télécharge sur cet appareil les photos des membres '
                          'téléversées par l\'administrateur sur le site web '
                          '(répertoire photos), afin qu\'elles restent '
                          'disponibles dans les contrats même SANS connexion '
                          'internet par la suite.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _downloadingPhotos
                                ? null
                                : _downloadPhotos,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: OkapiColors.primary,
                              side: const BorderSide(
                                color: OkapiColors.primary,
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                            ),
                            icon: _downloadingPhotos
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.photo_library_rounded),
                            label: Text(
                              _downloadingPhotos
                                  ? (_photosTotal > 0
                                        ? 'Téléchargement… $_photosDone/$_photosTotal'
                                        : 'Préparation…')
                                  : 'Télécharger les photos pour utilisation hors-ligne',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        if (_photosResultMessage != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _photosResultOk == true
                                  ? OkapiColors.secondary.withValues(
                                      alpha: 0.08,
                                    )
                                  : Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _photosResultOk == true
                                    ? OkapiColors.secondary.withValues(
                                        alpha: 0.3,
                                      )
                                    : Colors.red.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              _photosResultMessage!,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  const _CountChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12.5, color: color)),
        ],
      ),
    );
  }
}
