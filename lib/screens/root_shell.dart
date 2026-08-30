import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../services/app_data_provider.dart';
import 'dashboard/dashboard_screen.dart';
import 'dashboard/module_dashboard_screen.dart';
import 'menage/menage_list_screen.dart';
import 'champs/champs_list_screen.dart';
import 'structures/structures_list_screen.dart';
import 'contracts/contracts_screen.dart';
import 'sync/sync_screen.dart';
import 'survey/survey_module_screen.dart';

/// Main app shell shown once the user is logged in AND has chosen a
/// project + module. The set of screens/nav items shown is built
/// DYNAMICALLY from [moduleCode] so the 3 modules are TOTALLY separated:
///   - PARC          -> Tableau de bord, Ménages, Champs, Structures,
///                      Contrats, Synchroniser (everything related to
///                      compensation contracts lives here and ONLY here).
///   - BIODIVERSITÉ  -> Tableau de bord (biodiversité), formulaires
///                      biodiversité, Synchroniser.
///   - SOCIAL        -> Tableau de bord (social), formulaires social,
///                      Synchroniser.
/// [moduleCode] itself is already constrained to what the user's statut
/// allows (see ModuleSelectScreen / SessionService.allowedModulesForStatut),
/// so no further statut check is needed here — but as a defensive
/// safety-net the "Changer de module" action re-routes through
/// ModuleSelectScreen rather than allowing a direct switch to a
/// disallowed module.
class RootShell extends StatefulWidget {
  final AppUser currentUser;
  final String projectCode;
  final String moduleCode;
  final VoidCallback onLogout;
  final VoidCallback onChangeModule;
  final VoidCallback onChangeProject;

  const RootShell({
    super.key,
    required this.currentUser,
    required this.projectCode,
    required this.moduleCode,
    required this.onLogout,
    required this.onChangeModule,
    required this.onChangeProject,
  });

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Wire the active project into AppDataProvider so its menages/champs/
    // structures getters are filtered to ONLY this project's records (see
    // AppDataProvider.setProject) — this is what actually enforces the
    // per-project household/champ/structure isolation once a project has
    // been selected.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppDataProvider>().setProject(widget.projectCode);
    });
  }

  List<Widget> get _screens {
    switch (widget.moduleCode) {
      case 'biodiversite':
        return const [
          ModuleDashboardScreen(
            module: 'BIODIVERSITE',
            moduleTitle: 'Biodiversité',
            accentColor: OkapiColors.secondary,
          ),
          SurveyModuleScreen(module: 'BIODIVERSITE', moduleTitle: 'Biodiversité'),
          SyncScreen(),
        ];
      case 'social':
        return const [
          ModuleDashboardScreen(
            module: 'SOCIAL',
            moduleTitle: 'Social',
            accentColor: OkapiColors.primary,
          ),
          SurveyModuleScreen(module: 'SOCIAL', moduleTitle: 'Social'),
          SyncScreen(),
        ];
      default: // 'parc'
        return [
          const DashboardScreen(),
          const MenageListScreen(),
          ChampsListScreen(projectCode: widget.projectCode),
          StructuresListScreen(projectCode: widget.projectCode),
          ContractsScreen(projectCode: widget.projectCode),
          const SyncScreen(),
        ];
    }
  }

  List<_NavItem> get _items {
    switch (widget.moduleCode) {
      case 'biodiversite':
        return const [
          _NavItem(icon: Icons.dashboard_rounded, label: 'Tableau de bord'),
          _NavItem(icon: Icons.eco_rounded, label: 'Formulaires'),
          _NavItem(icon: Icons.cloud_upload_rounded, label: 'Synchroniser'),
        ];
      case 'social':
        return const [
          _NavItem(icon: Icons.dashboard_rounded, label: 'Tableau de bord'),
          _NavItem(icon: Icons.people_alt_rounded, label: 'Formulaires'),
          _NavItem(icon: Icons.cloud_upload_rounded, label: 'Synchroniser'),
        ];
      default: // 'parc'
        return const [
          _NavItem(icon: Icons.dashboard_rounded, label: 'Tableau de bord'),
          _NavItem(icon: Icons.groups_rounded, label: 'Ménages'),
          _NavItem(icon: Icons.grass_rounded, label: 'Champs'),
          _NavItem(icon: Icons.home_work_rounded, label: 'Structures'),
          _NavItem(icon: Icons.description_rounded, label: 'Contrats'),
          _NavItem(icon: Icons.cloud_upload_rounded, label: 'Synchroniser'),
        ];
    }
  }

  String get _moduleLabel => SessionService.labelForModule(widget.moduleCode);
  String get _projectLabel =>
      SessionService.labelForProject(widget.projectCode);

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: Text(
          'Voulez-vous vraiment vous déconnecter, ${widget.currentUser.nomPrenom} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onLogout();
    }
  }

  void _showSwitchMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.apps_rounded),
              title: const Text('Changer de module'),
              subtitle: Text('Actuellement : $_moduleLabel'),
              onTap: () {
                Navigator.of(ctx).pop();
                widget.onChangeModule();
              },
            ),
            ListTile(
              leading: const Icon(Icons.map_rounded),
              title: const Text('Changer de projet'),
              subtitle: Text('Actuellement : $_projectLabel'),
              onTap: () {
                Navigator.of(ctx).pop();
                widget.onChangeProject();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant RootShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moduleCode != widget.moduleCode && _index != 0) {
      setState(() => _index = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final screens = _screens;
    final items = _items;
    final safeIndex = _index < screens.length ? _index : 0;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: safeIndex,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              backgroundColor: Colors.white,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: OkapiColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.eco, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'OKAPI',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: OkapiColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _projectLabel,
                      style: const TextStyle(fontSize: 10),
                    ),
                    Text(
                      _moduleLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: OkapiColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    IconButton(
                      tooltip: 'Changer de module / projet',
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      onPressed: () => _showSwitchMenu(context),
                    ),
                  ],
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Text(
                          widget.currentUser.nomPrenom,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        IconButton(
                          tooltip: 'Déconnexion',
                          icon: const Icon(Icons.logout_rounded),
                          onPressed: _confirmLogout,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              destinations: items
                  .map(
                    (e) => NavigationRailDestination(
                      icon: Icon(e.icon),
                      selectedIcon: Icon(e.icon, color: OkapiColors.primary),
                      label: Text(e.label),
                    ),
                  )
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: screens[safeIndex]),
          ],
        ),
      );
    }

    return Scaffold(
      body: screens[safeIndex],
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'switchFab',
            tooltip: 'Changer de module / projet',
            backgroundColor: OkapiColors.secondary,
            onPressed: () => _showSwitchMenu(context),
            child: const Icon(Icons.swap_horiz_rounded, color: Colors.white),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: 'logoutFab',
            tooltip: 'Déconnexion (${widget.currentUser.nomPrenom})',
            backgroundColor: OkapiColors.primary,
            onPressed: _confirmLogout,
            child: const Icon(Icons.logout_rounded, color: Colors.white),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: safeIndex,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        iconSize: 22,
        items: items
            .map(
              (e) =>
                  BottomNavigationBarItem(icon: Icon(e.icon), label: e.label),
            )
            .toList(),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
