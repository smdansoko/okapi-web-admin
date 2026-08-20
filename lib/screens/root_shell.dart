import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import 'dashboard/dashboard_screen.dart';
import 'menage/menage_list_screen.dart';
import 'champs/champs_list_screen.dart';
import 'structures/structures_list_screen.dart';
import 'contracts/contracts_screen.dart';
import 'sync/sync_screen.dart';

class RootShell extends StatefulWidget {
  final AppUser currentUser;
  final VoidCallback onLogout;

  const RootShell({
    super.key,
    required this.currentUser,
    required this.onLogout,
  });

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  final _screens = const [
    DashboardScreen(),
    MenageListScreen(),
    ChampsListScreen(),
    StructuresListScreen(),
    ContractsScreen(),
    SyncScreen(),
  ];

  final _items = const [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Tableau de bord'),
    _NavItem(icon: Icons.groups_rounded, label: 'Ménages'),
    _NavItem(icon: Icons.grass_rounded, label: 'Champs'),
    _NavItem(icon: Icons.home_work_rounded, label: 'Structures'),
    _NavItem(icon: Icons.description_rounded, label: 'Contrats'),
    _NavItem(icon: Icons.cloud_upload_rounded, label: 'Synchroniser'),
  ];

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

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
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
              destinations: _items
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
            Expanded(child: _screens[_index]),
          ],
        ),
      );
    }

    return Scaffold(
      body: _screens[_index],
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'logoutFab',
        tooltip: 'Déconnexion (${widget.currentUser.nomPrenom})',
        backgroundColor: OkapiColors.primary,
        onPressed: _confirmLogout,
        child: const Icon(Icons.logout_rounded, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        iconSize: 22,
        items: _items
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
