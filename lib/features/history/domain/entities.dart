import 'package:equatable/equatable.dart';

class OpLog extends Equatable {
  final int? id;
  final String kind; // 'ubnt' | 'tplink'
  final String detail;
  final bool ok;
  final DateTime at;
  const OpLog({this.id, required this.kind, required this.detail, required this.ok, required this.at});
  @override
  List<Object?> get props => [id, kind, detail, ok, at];
}
