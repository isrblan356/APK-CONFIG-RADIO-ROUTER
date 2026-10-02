import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../network/reachability.dart';
import '../../features/radio_ubiquiti/data/ubnt_repository_impl.dart';
import '../../features/radio_ubiquiti/domain/repositories/ubnt_repository.dart';
import '../../features/router_tplink/data/tplink_repository_impl.dart';
import '../../features/inventory/data/inventory_local.dart';
import '../../features/inventory/domain/inventory_repository.dart';
import '../../features/history/data/history_repository_impl.dart';
import '../../features/history/domain/history_repository.dart';

// DI centralizada. Las páginas importan SOLO este archivo (nunca main.dart).
final httpClientProvider = Provider<http.Client>((ref) => http.Client());
final reachabilityProvider = Provider<Reachability>((ref) => ReachabilityImpl());
final inventoryProvider =
    Provider<InventoryRepository>((ref) => InventoryLocal(ref.watch(httpClientProvider)));
final ubntRepoProvider = Provider<UbntRepository>((ref) =>
    UbntRepositoryImpl(ref.watch(reachabilityProvider), ref.watch(inventoryProvider)));
final tplinkRepoProvider =
    Provider<TplinkRepository>((ref) => TplinkRepositoryImpl(ref.watch(httpClientProvider)));
final historyProvider =
    Provider<HistoryRepository>((ref) => HistoryRepositoryImpl());
