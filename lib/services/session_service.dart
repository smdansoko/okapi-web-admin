import 'package:shared_preferences/shared_preferences.dart';

/// One of the 3 OKAPI projects a field agent can be assigned to.
class ProjectOption {
  final String code; // simandou / wcag / smb
  final String label; // SIMANDOU / WCAG / SMB
  const ProjectOption(this.code, this.label);
}

/// One of the 3 survey modules. Mirrors the OKAPI Web Admin's own
/// project/module selection flow (see okapi_web_admin/auth.py) so the
/// mobile app and the web admin present the exact same navigation model.
class ModuleOption {
  final String code; // parc / biodiversite / social
  final String label; // PARC / BIODIVERSITÉ / SOCIAL
  const ModuleOption(this.code, this.label);
}

/// Persists the field agent's chosen PROJECT (SIMANDOU/WCAG/SMB) and MODULE
/// (PARC/BIODIVERSITÉ/SOCIAL) for the current session, and determines which
/// modules a given account "statut" is allowed to use.
///
/// Total separation rule (per requirement): everything related to
/// compensation contracts (Ménages, Champs, Structures, Contrats,
/// Compensation, Facturation, Rapport, Photos) lives exclusively under
/// PARC. BIODIVERSITÉ forms are reachable only when BIODIVERSITÉ is the
/// active module, and likewise for SOCIAL. Which modules are even
/// SELECTABLE is further restricted by the account's "statut":
///   - "Chef d'équipe" / "Enquêteur"      -> PARC only
///   - "Expert Biodiversité"              -> BIODIVERSITÉ only
///   - "Expert Social"                    -> SOCIAL only
///   - "Administrateur principal"         -> all 3 (the web admin's main
///                                          account, also usable from the
///                                          mobile app - see AuthService)
///   - any other/unknown statut (legacy)  -> all 3 (safe fallback)
class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  static const _prefKeyProject = 'session_project';
  static const _prefKeyModule = 'session_module';

  String? _cachedProject;
  String? _cachedModule;

  static const List<ProjectOption> projects = [
    ProjectOption('simandou', 'SIMANDOU'),
    ProjectOption('wcag', 'WCAG'),
    ProjectOption('smb', 'SMB'),
  ];

  static const List<ModuleOption> modules = [
    ModuleOption('parc', 'PARC'),
    ModuleOption('biodiversite', 'BIODIVERSITÉ'),
    ModuleOption('social', 'SOCIAL'),
  ];

  static const String kChefDEquipe = "Chef d'équipe";
  static const String kEnqueteur = 'Enquêteur';
  static const String kExpertBiodiversite = 'Expert Biodiversité';
  static const String kExpertSocial = 'Expert Social';
  // Statut assigned to the OKAPI Web Admin's main administrator account
  // (dsmariame) when it logs in from the mobile app - see AuthService.login.
  // Grants full access to all 3 modules (PARC + BIODIVERSITÉ + SOCIAL).
  static const String kAdministrateurPrincipal = 'Administrateur principal';

  /// Which module codes ('parc' / 'biodiversite' / 'social') the given
  /// account "statut" is allowed to select/use.
  static Set<String> allowedModulesForStatut(String statut) {
    switch (statut) {
      case kChefDEquipe:
      case kEnqueteur:
        return {'parc'};
      case kExpertBiodiversite:
        return {'biodiversite'};
      case kExpertSocial:
        return {'social'};
      case kAdministrateurPrincipal:
        return {'parc', 'biodiversite', 'social'};
      default:
        // Legacy/unknown statut: don't lock the user out of the app.
        return {'parc', 'biodiversite', 'social'};
    }
  }

  Future<String?> get project async {
    if (_cachedProject != null) return _cachedProject;
    final prefs = await SharedPreferences.getInstance();
    _cachedProject = prefs.getString(_prefKeyProject);
    return _cachedProject;
  }

  Future<String?> get module async {
    if (_cachedModule != null) return _cachedModule;
    final prefs = await SharedPreferences.getInstance();
    _cachedModule = prefs.getString(_prefKeyModule);
    return _cachedModule;
  }

  Future<void> setProject(String code) async {
    _cachedProject = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyProject, code);
  }

  Future<void> setModule(String code) async {
    _cachedModule = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyModule, code);
  }

  /// Clears only the module selection (used by "Changer de module").
  Future<void> clearModule() async {
    _cachedModule = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyModule);
  }

  /// Clears both project and module (used by "Changer de projet" and on
  /// logout).
  Future<void> clearAll() async {
    _cachedProject = null;
    _cachedModule = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyProject);
    await prefs.remove(_prefKeyModule);
  }

  static String labelForProject(String? code) {
    return projects.firstWhere(
      (p) => p.code == code,
      orElse: () => const ProjectOption('', ''),
    ).label;
  }

  static String labelForModule(String? code) {
    return modules.firstWhere(
      (m) => m.code == code,
      orElse: () => const ModuleOption('', ''),
    ).label;
  }
}
