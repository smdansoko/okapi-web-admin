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
import '../../services/storage_service.dart';
import '../../services/survey_data_provider.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// Statuts allowed to reset ALL locally saved data on THIS device
/// (superficie parcelles, champs, ménages, fiches BIODIVERSITÉ/SOCIAL,
/// etc.) without touching the survey forms/schemas themselves (the forms
/// are bundled app assets, not stored in Hive, so they are never affected
/// by this action regardless). Restricted to avoid an Enquêteur
/// accidentally wiping a whole team's unsynced field work.
const Set<String> _kResetAllowedStatuts = {
  "Chef d'équipe",
  SessionService.kAdministrateurPrincipal,
};

/// Every "statut" is allowed to push data to the server via
/// "Synchroniser" (PUSH) AND pull via "Actualiser", EXCEPT "Enquêteur"
/// which may only pull ("Actualiser"). This lets "Chef d'équipe",
/// "Expert Biodiversité", "Expert Social" and "Administrateur principal"
/// (including admin accounts logging in from the mobile app) trigger
/// synchronization.
const String _kChefDEquipeStatut = "Chef d'équipe";
const Set<String> _kPushDeniedStatuts = {SessionService.kEnqueteur};

/// "Synchroniser" tab: lets the field team push all locally collected data
/// to the separate OKAPI Web Admin server, where it becomes available for
/// contract PDF export and compensation table (Excel) export.
///
/// Synchronization is now scoped PER MODULE via [moduleCode]
/// ('parc' / 'biodiversite' / 'social'), mirroring the total separation
/// already enforced elsewhere in the app (RootShell/SessionService):
///   - PARC          -> pushes/pulls ONLY Ménages, Enquêtes Champs,
///                      Enquêtes Structures (+ photos/contrats-related
///                      data, handled by their own dedicated sections
///                      further down this screen).
///   - BIODIVERSITÉ  -> pushes/pulls ONLY the 8 BIODIVERSITÉ survey forms.
///   - SOCIAL        -> pushes/pulls ONLY the 3 SOCIAL survey forms.
class SyncScreen extends StatefulWidget {
  final String moduleCode; // 'parc' / 'biodiversite' / 'social'
  const SyncScreen({super.key, this.moduleCode = 'parc'});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _urlController = TextEditingController();

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

  // ---- Reset local data state ----
  bool _resettingData = false;

  AppUser? _currentUser;
  bool get _canSynchronize =>
      _currentUser != null &&
      !_kPushDeniedStatuts.contains(_currentUser!.statut);

  /// Only the main administrator account may see/edit the server URL —
  /// every other user gets a fixed, hidden server address (still fully
  /// functional under the hood, just not shown/editable in the UI).
  bool get _isAdmin =>
      _currentUser?.statut == SessionService.kAdministrateurPrincipal;

  /// "Nom de cet appareil" is now ALWAYS the currently logged-in user's
  /// own name — never freely editable — so every sync/log entry on the
  /// server is unambiguously traceable to the person who sent it.
  String get _deviceDisplayName => (_currentUser?.nomPrenom.isNotEmpty ?? false)
      ? _currentUser!.nomPrenom
      : 'Utilisateur inconnu';

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
    // Keep the persisted "device name" in sync with the current user's own
    // name, so every sync request sent to the server is correctly
    // attributed even though the field is no longer editable.
    if (user != null) {
      await SyncService.instance.setDeviceName(user.nomPrenom);
    }
  }

  Future<void> _loadPrefs() async {
    final url = await SyncService.instance.serverUrl;
    final last = await SyncService.instance.lastSyncAt;
    if (!mounted) return;
    setState(() {
      _urlController.text = url;
      _lastSyncAt = last;
      _loadingPrefs = false;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _saveServerSettings() async {
    // The server URL is only ever changed via the (admin-only) text field;
    // for non-admin users _urlController simply mirrors the already-saved
    // value untouched, so saving it back is harmless.
    await SyncService.instance.setServerUrl(_urlController.text);
    await SyncService.instance.setDeviceName(_deviceDisplayName);
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
  /// tablette" requirement, AND to the current module ('parc' /
  /// 'biodiversite' / 'social') — total separation: PARC synchronizes
  /// ONLY Ménages/Champs/Structures (+ their photos/contrats, handled by
  /// their own dedicated sections further down), BIODIVERSITÉ and SOCIAL
  /// never touch this PARC data at all. Each Menage/EnqueteChamp/
  /// EnqueteStructure record carries its own `tablette` field (filled in
  /// via the "Tablette" dropdown on the survey forms). If the logged-in
  /// chef has no tablette assigned to their account (older accounts
  /// created before this field existed), sync is not restricted
  /// (backward compatibility) but a warning is shown so the issue can be
  /// corrected.
  ({
    List<Menage> menages,
    List<EnqueteChamp> champs,
    List<EnqueteStructure> structures,
  })
  _dataForSync(AppDataProvider data) {
    if (widget.moduleCode != 'parc') {
      return (menages: const [], champs: const [], structures: const []);
    }
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

  /// The survey form keys ('pose_cameras', 'patrimoine_culturel', etc.)
  /// relevant to the CURRENT module only — PARC has none (its data is
  /// Ménages/Champs/Structures, handled by [_dataForSync] instead).
  List<String> get _formKeysForModule {
    switch (widget.moduleCode) {
      case 'biodiversite':
        return kBiodiversiteFormKeys;
      case 'social':
        return kSocialFormKeys;
      default:
        return const [];
    }
  }

  Future<void> _synchronize() async {
    if (!_canSynchronize) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Le statut "${SessionService.kEnqueteur}" ne peut pas '
            'effectuer la synchronisation (envoi vers le serveur). '
            'Utilisez "Actualiser" pour récupérer les données, ou '
            'contactez votre "$_kChefDEquipeStatut" pour l\'envoi.',
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
      for (final key in _formKeysForModule) key: surveyData.recordsFor(key),
    };

    setState(() {
      _syncing = true;
      _lastResult = null;
    });

    // Ménage/Champ/Structure deletion tombstones only ever apply to PARC —
    // never sent alongside a BIODIVERSITÉ/SOCIAL-only sync.
    final pendingDeletions = widget.moduleCode == 'parc'
        ? data.pendingDeletions
        : <Map<String, dynamic>>[];

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
      // Total separation on pull too: PARC only merges Ménages/Champs/
      // Structures; BIODIVERSITÉ/SOCIAL only merge their own survey
      // records (filtered to this module's form keys), even though the
      // server response itself contains everything for the project.
      if (widget.moduleCode == 'parc') {
        await data.mergeFromServer(
          menages: result.menages,
          champs: result.champs,
          structures: result.structures,
          deletions: result.deletions,
        );
      } else {
        final allowedKeys = _formKeysForModule.toSet();
        final filteredRecords = {
          for (final entry in result.surveyRecords.entries)
            if (allowedKeys.contains(entry.key)) entry.key: entry.value,
        };
        await surveyData.mergeFromServer(filteredRecords);
      }
    }

    if (!mounted) return;
    setState(() {
      _pulling = false;
      _lastPullResult = result;
      if (result.success) _lastSyncAt = DateTime.now();
    });

    if (result.success) {
      final summary = widget.moduleCode == 'parc'
          ? 'Ménages: ${result.menages.length} · '
                'Champs: ${result.champs.length} · '
                'Structures: ${result.structures.length}'
          : '${SessionService.labelForModule(widget.moduleCode)}: '
                '${_formKeysForModule.fold<int>(0, (sum, k) => sum + (result.surveyRecords[k]?.length ?? 0))} '
                'fiche(s)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Actualisation réussie ✔ — $summary'),
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

  bool get _canResetData =>
      _currentUser != null &&
      _kResetAllowedStatuts.contains(_currentUser!.statut);

  /// Wipes ALL data currently saved locally on THIS device (Ménages,
  /// Enquêtes Champs/Structures — superficie parcelles, etc. — and every
  /// BIODIVERSITÉ/SOCIAL fiche), WITHOUT touching the survey forms
  /// themselves (the form definitions are a bundled app asset, never
  /// stored in Hive, so they are never affected). Requires typing
  /// "REINITIALISER" to confirm, since this is destructive and cannot be
  /// undone for any data not already synchronized to the server.
  Future<void> _confirmResetData() async {
    final confirmController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Réinitialiser les données locales ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cette action supprime DÉFINITIVEMENT de cet appareil : les '
              'ménages, les enquêtes champs (superficie des parcelles, '
              'cultures, etc.), les enquêtes structures, ainsi que toutes '
              'les fiches BIODIVERSITÉ/SOCIAL enregistrées localement.\n\n'
              'Les FORMULAIRES eux-mêmes (questions/schémas) ne sont PAS '
              'touchés. Toute donnée non encore synchronisée sera perdue.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Tapez REINITIALISER pour confirmer :',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'REINITIALISER',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.of(ctx).pop(
              confirmController.text.trim().toUpperCase() == 'REINITIALISER',
            ),
            child: const Text(
              'Réinitialiser',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _resettingData = true);
    await StorageService.instance.clearAll();
    if (!mounted) return;
    final data = context.read<AppDataProvider>();
    final surveyData = context.read<SurveyDataProvider>();
    await data.loadAll();
    if (!mounted) return;
    await surveyData.loadAll(kAllSurveyFormKeys);
    if (!mounted) return;
    setState(() => _resettingData = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Données locales réinitialisées. Les formulaires restent '
          'inchangés. Utilisez "Actualiser" pour récupérer les données '
          'depuis le serveur.',
        ),
        backgroundColor: OkapiColors.secondary,
      ),
    );
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
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
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
                            // PARC-only chips: Ménages/Individus/Champs/
                            // Structures never shown while in the
                            // BIODIVERSITÉ or SOCIAL module (total
                            // separation between modules).
                            if (widget.moduleCode == 'parc') ...[
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
                            ],
                            // BIODIVERSITÉ-only chip: never shown in PARC
                            // or SOCIAL.
                            if (widget.moduleCode == 'biodiversite')
                              _CountChip(
                                icon: Icons.eco_rounded,
                                label: 'Biodiversité',
                                count: surveyData.totalBiodiversiteRecords,
                                color: OkapiColors.secondary,
                              ),
                            // SOCIAL-only chip: never shown in PARC or
                            // BIODIVERSITÉ.
                            if (widget.moduleCode == 'social')
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
                                widget.moduleCode == 'parc'
                                    ? 'Inclut les photos (profil + CNI recto/verso), le numéro de lot '
                                          '(N° de batch) et toutes les informations des contrats.'
                                    : 'Seules les fiches du module '
                                          '${SessionService.labelForModule(widget.moduleCode)} '
                                          'sont concernées par cette synchronisation.',
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
                        // The server address is only ever visible/editable
                        // by the main administrator account — every other
                        // user gets a discreet "connected" indicator
                        // instead, without exposing the underlying URL.
                        if (_isAdmin)
                          TextField(
                            controller: _urlController,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'Adresse du serveur (URL)',
                              hintText: 'https://exemple.okapi-admin.com',
                              prefixIcon: Icon(Icons.link),
                              border: OutlineInputBorder(),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lock_outline,
                                  size: 18,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Serveur configuré par l\'administrateur principal.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        // "Nom de cet appareil" = the logged-in user's own
                        // name, always, never editable — every sync
                        // request is unambiguously traceable to the
                        // person who sent it.
                        TextField(
                          enabled: false,
                          controller: TextEditingController(
                            text: _deviceDisplayName,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Nom de cet appareil',
                            prefixIcon: Icon(Icons.person_outline),
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
                        // Nothing left to manually save for non-admins:
                        // the server URL is fixed/hidden and the device
                        // name is now always the logged-in user's own
                        // name (synced automatically in _loadCurrentUser).
                        if (_isAdmin) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _saveServerSettings,
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: const Text('Enregistrer les paramètres'),
                          ),
                        ],
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
                          'Le statut "${SessionService.kEnqueteur}" ne peut '
                          'pas synchroniser (envoi). Votre statut actuel : '
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
                        widget.moduleCode == 'parc'
                            ? 'Récupère les ménages, enquêtes champs et structures enregistrés '
                                  'sur les AUTRES tablettes et les rend immédiatement disponibles '
                                  'ici (listes déroulantes Ménage / Propriétaire).'
                            : 'Récupère les fiches ${SessionService.labelForModule(widget.moduleCode)} '
                                  'enregistrées sur les AUTRES tablettes.',
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
                            widget.moduleCode == 'parc'
                                ? 'Reçu du serveur — Ménages: ${_lastPullResult!.menages.length} · '
                                      'Champs: ${_lastPullResult!.champs.length} · '
                                      'Structures: ${_lastPullResult!.structures.length}'
                                : 'Reçu du serveur — '
                                      '${_formKeysForModule.fold<int>(0, (sum, k) => sum + (_lastPullResult!.surveyRecords[k]?.length ?? 0))} '
                                      'fiche(s) ${SessionService.labelForModule(widget.moduleCode)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // ---- Photos hors-ligne (téléchargement des photos web) ----
                // PARC-only: member photos are only ever used in
                // compensation contracts, which live exclusively under
                // PARC.
                if (widget.moduleCode == 'parc')
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

                // ---- Réinitialiser les données locales ----
                if (_canResetData)
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.delete_forever_rounded,
                                color: Colors.red.shade700,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Réinitialiser les données locales',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Supprime de CET appareil uniquement les ménages, '
                            'champs (superficie des parcelles, etc.), '
                            'structures et fiches BIODIVERSITÉ/SOCIAL '
                            'enregistrés localement, SANS toucher aux '
                            'formulaires. Pensez à synchroniser avant, sinon '
                            'les données non envoyées seront perdues.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _resettingData
                                  ? null
                                  : _confirmResetData,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade700),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              icon: _resettingData
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.delete_forever_rounded),
                              label: Text(
                                _resettingData
                                    ? 'Réinitialisation…'
                                    : 'Réinitialiser les données locales',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
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
