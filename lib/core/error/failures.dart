// Capa core: errores y resultado funcional (clean code, sin excepciones en dominio).
import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);
  @override
  List<Object> get props => [message];
}

class ConnectionFailure extends Failure {
  const ConnectionFailure(super.message);
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class DeviceFailure extends Failure {
  const DeviceFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class CacheFailure extends Failure {
  const CacheFailure(super.message);
}
