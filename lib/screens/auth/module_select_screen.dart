import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';

/// Second screen shown after choosing a project: choose the MODULE (PARC,
/// BIODIVERSITÉ or SOCIAL). Which modules are selectable depends on the
/// logged-in account's "statut" (see SessionService.allowedModulesForStatut):
///   - Chef d'équipe / Enquêteur   -> only PARC is enabled
///   - Expert Biodiversité         -> only BIODIVERSITÉ is enabled
///   - Expert Social               -> only SOCIAL is enabled
/// Disabled tiles are shown greyed-out (mirrors the web admin's
/// "à venir" disabled-tile style, but here disabled = "not for your
/// statut" instead of "not implemented yet").
class ModuleSelectScreen extends StatelessWidget {
  final AppUser currentUser;
  final String projectCode;
  final void Function(String moduleCode) onModuleSelected;
  final VoidCallback onChangeProject;
  final VoidCallback onLogout;

  const ModuleSelectScreen({
    super.key,
    required this.currentUser,
    required this.projectCode,
    required this.onModuleSelected,
    required this.onChangeProject,
    required this.onLogout,
  });

  Future<void> _choose(String code) async {
    await SessionService.instance.setModule(code);
    onModuleSelected(code);
  }

  @override
  Widget build(BuildContext context) {
    final allowed = SessionService.allowedModulesForStatut(
      currentUser.statut,
    );
    final projectLabel = SessionService.labelForProject(projectCode);

    return Scaffold(
      backgroundColor: OkapiColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/logo/okapi_logo_full.png',
                      height: 80,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Projet $projectLabel',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: OkapiColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sélectionnez un module',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: OkapiColors.textLight),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Statut : ${currentUser.statut}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: OkapiColors.textLight,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 28),
                  ...SessionService.modules.map((m) {
                    final enabled = allowed.contains(m.code);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ModuleTile(
                        icon: _iconFor(m.code),
                        label: m.label,
                        enabled: enabled,
                        onTap: enabled ? () => _choose(m.code) : null,
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: onChangeProject,
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Changer de projet'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: onLogout,
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Déconnexion'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String code) {
    switch (code) {
      case 'biodiversite':
        return Icons.eco_rounded;
      case 'social':
        return Icons.people_alt_rounded;
      default:
        return Icons.description_rounded;
    }
  }
}

class _ModuleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;
  const _ModuleTile({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? OkapiColors.primary : Colors.grey;
    return Material(
      color: enabled ? Colors.white : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(14),
      elevation: enabled ? 1.5 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled
                  ? OkapiColors.primary.withValues(alpha: 0.18)
                  : Colors.grey.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              if (!enabled)
                Text(
                  'Non autorisé',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: OkapiColors.textLight,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
