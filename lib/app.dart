import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/ar_compass/presentation/ar_page.dart';
import 'features/history/presentation/history_page.dart';
import 'features/radio_ubiquiti/presentation/ubnt_page.dart';
import 'features/router_tplink/presentation/tplink_page.dart';
import 'features/inventory/presentation/zones_page.dart';

class IspApp extends StatelessWidget {
  const IspApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ISP CONFIG',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomeTabs(),
    );
  }
}

class HomeTabs extends ConsumerStatefulWidget {
  const HomeTabs({super.key});
  @override
  ConsumerState<HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends ConsumerState<HomeTabs> {
  int i = 0;
  @override
  Widget build(BuildContext context) {
    const pages = [ZonesPage(), UbntPage(), TplinkPage(), ArPage(), HistoryPage()];
    return Scaffold(
      body: pages[i],
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) => setState(() => i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map), label: 'Zonas/APs'),
          NavigationDestination(icon: Icon(Icons.radio), label: 'Radio'),
          NavigationDestination(icon: Icon(Icons.router), label: 'Router'),
          NavigationDestination(icon: Icon(Icons.explore), label: 'Brújula'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
        ],
      ),
    );
  }
}
