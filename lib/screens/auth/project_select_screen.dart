import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';

/// First screen shown right after login: choose the PROJECT (SIMANDOU,
/// WCAG or SMB) this session will operate on. Mirrors the OKAPI Web
/// Admin's own /select-project step so the mobile app and the web admin
/// present the exact same navigation flow.
class ProjectSelectScreen extends StatelessWidget {
  final AppUser currentUser;
  final void Function(String projectCode) onProjectSelected;
  final VoidCallback onLogout;

  const ProjectSelectScreen({
    super.key,
    required this.currentUser,
    required this.onProjectSelected,
    required this.onLogout,
  });

  Future<void> _choose(BuildContext context, String code) async {
    await SessionService.instance.setProject(code);
    onProjectSelected(code);
  }

  @override
  Widget build(BuildContext context) {
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
                  ClipOval(
                    child: Image.asset(
                      'assets/logo/okapi_icon_circular.png',
                      height: 80,
                      width: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Sélectionnez un projet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: OkapiColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Connecté en tant que ${currentUser.nomPrenom}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: OkapiColors.textLight),
                  ),
                  const SizedBox(height: 28),
                  ...SessionService.projects.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ProjectTile(
                        label: p.label,
                        onTap: () => _choose(context, p.code),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Se déconnecter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ProjectTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: OkapiColors.primary.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: OkapiColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.map_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: OkapiColors.primary,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: OkapiColors.textLight),
            ],
          ),
        ),
      ),
    );
  }
}
