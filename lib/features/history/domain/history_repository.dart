import 'entities.dart';

abstract class HistoryRepository {
  Future<void> add(String kind, String detail, bool ok);
  Future<List<OpLog>> recent({int limit = 100});
  Future<void> clear();
}
