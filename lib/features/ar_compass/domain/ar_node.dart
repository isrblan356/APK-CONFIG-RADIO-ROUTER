import 'package:equatable/equatable.dart';

/// Nodo con coordenadas para apuntar la antena (AR / brújula).
///
/// [origen]: 'manual' (lo agregó el usuario en el móvil) o 'nube'
/// (vino de GET $CLOUD_ENDPOINT/nodes). Solo los de nube se reemplazan al
/// sincronizar: lo manual nunca se borra.
class ArNode extends Equatable {
  final int localId; // PK local (0 si aún no se guardó)
  final int? remotoId; // id del servidor (null en los manuales)
  final String nombre;
  final double lat;
  final double lng;
  final double? alt; // metros sobre el nivel del mar (opcional)
  final String zona;
  final String origen;

  const ArNode({
    required this.nombre,
    required this.lat,
    required this.lng,
    this.localId = 0,
    this.remotoId,
    this.alt,
    this.zona = '',
    this.origen = 'manual',
  });

  ArNode copyWith({int? localId}) => ArNode(
        localId: localId ?? this.localId,
        remotoId: remotoId,
        nombre: nombre,
        lat: lat,
        lng: lng,
        alt: alt,
        zona: zona,
        origen: origen,
      );

  @override
  List<Object?> get props =>
      [localId, remotoId, nombre, lat, lng, alt, zona, origen];
}
