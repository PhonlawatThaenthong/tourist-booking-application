import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import 'dashboard_screen.dart';
import 'manage_bookings_screen.dart';
import 'manage_rooms_screen.dart';
import 'manage_staff_screen.dart';
import 'reports_screen.dart';

/// Back-office shell. Uses a NavigationRail on wide screens and a Drawer on
/// phones. Staff management is restricted to admins (role-based permissions).
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser!;
    final isAdmin = user.role == UserRole.admin;

    final destinations = <_NavItem>[
      const _NavItem(Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
      const _NavItem(
          Icons.event_note_outlined, Icons.event_note, 'Bookings'),
      const _NavItem(Icons.king_bed_outlined, Icons.king_bed, 'Rooms'),
      const _NavItem(Icons.bar_chart_outlined, Icons.bar_chart, 'Reports'),
      if (isAdmin)
        const _NavItem(Icons.group_outlined, Icons.group, 'Staff'),
    ];

    final pages = <Widget>[
      const DashboardScreen(),
      const ManageBookingsScreen(),
      const ManageRoomsScreen(),
      const ReportsScreen(),
      if (isAdmin) const ManageStaffScreen(),
    ];

    if (_index >= pages.length) _index = 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('${destinations[_index].label} · ${user.role.label}'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (v) {
              if (v == 'logout') context.read<AuthProvider>().logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text('Signed in as ${user.name}'),
              ),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          if (wide) {
            return Row(
              children: [
                NavigationRail(
                  extended: constraints.maxWidth >= 1000,
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: constraints.maxWidth >= 1000
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  destinations: destinations
                      .map((d) => NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: pages[_index]),
              ],
            );
          }
          return pages[_index];
        },
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          // The NavigationRail handles navigation on wide layouts.
          if (MediaQuery.of(context).size.width >= 720) {
            return const SizedBox.shrink();
          }
          return NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: destinations
                .map((d) => NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label,
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.icon, this.selectedIcon, this.label);
}
