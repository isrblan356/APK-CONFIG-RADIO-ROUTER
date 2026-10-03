import '../domain/ar_node.dart';

/// Fusión pura entre lo local y lo que vino de la nube -> testeable.
///
/// Reglas:
/// * los nodos manuales (origen 'manual') jamás se tocan;
/// * los de nube se reemplazan completos por los de esta respuesta;
/// * si la respuesta viene vacía no se borra nada (un fallo parcial del
///   servidor no debe dejar al usuario sin sus nodos).
class ArNodeSync {
  ArNodeSync._();

  /// [local]: lo que hay hoy en el móvil. [nube]: lo que devolvió /nodes.
  /// Devuelve los locales que sobreviven + los que hay que insertar.
  static ({List<ArNode> conservar, List<ArNode> insertar}) plan(
      List<ArNode> local, List<ArNode> nube) {
    if (nube.isEmpty) return (conservar: local, insertar: const []);
    return (
      conservar: local.where((n) => n.origen != 'nube').toList(),
      insertar: nube,
    );
  }
}
