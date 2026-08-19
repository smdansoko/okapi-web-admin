import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'dashboard/dashboard_screen.dart';
import 'menage/menage_list_screen.dart';
import 'champs/champs_list_screen.dart';
import 'structures/structures_list_screen.dart';
import 'contracts/contracts_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

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
  ];

  final _items = const [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Tableau de bord'),
    _NavItem(icon: Icons.groups_rounded, label: 'Ménages'),
    _NavItem(icon: Icons.grass_rounded, label: 'Champs'),
    _NavItem(icon: Icons.home_work_rounded, label: 'Structures'),
    _NavItem(icon: Icons.description_rounded, label: 'Contrats'),
  ];

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
                    const Text('OKAPI', style: TextStyle(fontWeight: FontWeight.bold, color: OkapiColors.primary)),
                  ],
                ),
              ),
              destinations: _items
                  .map((e) => NavigationRailDestination(
                        icon: Icon(e.icon),
                        selectedIcon: Icon(e.icon, color: OkapiColors.primary),
                        label: Text(e.label),
                      ))
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: _items
            .map((e) => BottomNavigationBarItem(icon: Icon(e.icon), label: e.label))
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
