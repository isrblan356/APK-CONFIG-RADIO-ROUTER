import 'package:dartz/dartz.dart';
import '../../../core/error/failures.dart';
import 'entities.dart';

abstract class InventoryRepository {
  Future<Either<Failure, List<Zone>>> zones();
  Future<Either<Failure, List<AccessPoint>>> aps(String zoneId);
  Future<Either<Failure, void>> syncFromCloud(); // no-op si nube desactivada
}
