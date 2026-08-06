import 'package:flutter/services.dart';

/// Una lectura de UWB: distancia (m) y ángulo (grados) hacia el otro teléfono.
class UwbSample {
  final String type; // position | disconnected | error
  final double? distance; // metros
  final double? azimuth; // grados (dirección)
  final String? message;
  UwbSample(this.type, {this.distance, this.azimuth, this.message});
}

/// Puente con el código nativo (MainActivity.kt) que usa Jetpack UWB.
class UwbService {
  static const MethodChannel _m = MethodChannel('proxi/uwb');
  static const EventChannel _e = EventChannel('proxi/uwb_events');

  /// ¿Este teléfono tiene chip UWB?
  Future<bool> isAvailable() async {
    try {
      return (await _m.invokeMethod<bool>('isAvailable')) ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Rol "controller": devuelve un mapa con address (bytes), channel y preamble.
  Future<Map<String, dynamic>> prepareController() async {
    final r = await _m.invokeMethod('prepareController');
    return Map<String, dynamic>.from(r as Map);
  }

  /// Rol "controlee": devuelve un mapa con address (bytes).
  Future<Map<String, dynamic>> prepareControlee() async {
    final r = await _m.invokeMethod('prepareControlee');
    return Map<String, dynamic>.from(r as Map);
  }

  /// Inicia el ranging una vez intercambiados los parámetros por Firestore.
  Future<void> startRanging({
    required String role, // 'controller' | 'controlee'
    required List<int> peerAddress,
    required int sessionId,
    required List<int> sessionKey,
    required int channel,
    required int preamble,
  }) async {
    await _m.invokeMethod('startRanging', {
      'role': role,
      'peerAddress': peerAddress,
      'sessionId': sessionId,
      'sessionKey': sessionKey,
      'channel': channel,
      'preamble': preamble,
    });
  }

  Future<void> stop() async {
    try {
      await _m.invokeMethod('stop');
    } on PlatformException {
      // ignore
    }
  }

  /// Stream de lecturas UWB en vivo.
  Stream<UwbSample> get samples =>
      _e.receiveBroadcastStream().map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return UwbSample(
          (map['type'] as String?) ?? 'position',
          distance: (map['distance'] as num?)?.toDouble(),
          azimuth: (map['azimuth'] as num?)?.toDouble(),
          message: map['message'] as String?,
        );
      });
}
