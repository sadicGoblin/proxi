import 'dart:async';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart' as ble;
import 'package:permission_handler/permission_handler.dart';

/// Una lectura de proximidad Bluetooth (RSSI suavizado → distancia aprox.).
class BleSample {
  final int rssi;
  final double meters;
  BleSample(this.rssi, this.meters);
}

/// Proximidad "caliente/frío" entre dos teléfonos por BLE, SIN infraestructura.
/// Cada teléfono ANUNCIA un servicio Proxi y ESCUCHA al otro; el RSSI (intensidad)
/// se suaviza y se traduce en una distancia aproximada. Funciona en cualquier
/// teléfono con Bluetooth LE (incluida la gama media). Requiere calibración en cancha.
class BleProximity {
  // UUID fijo de Proxi (igual en ambos teléfonos)
  static final Guid serviceGuid = Guid('f47b1e10-1c3a-4b7e-9f00-9a1b2c3d4e5f');

  final _peripheral = ble.FlutterBlePeripheral();
  final _controller = StreamController<BleSample>.broadcast();
  StreamSubscription? _scanSub;
  double? _ema; // RSSI suavizado
  bool _running = false;

  Stream<BleSample> get samples => _controller.stream;

  Future<bool> ensurePermissions() async {
    final res = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return res.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<void> start() async {
    if (_running) return;
    if (!await ensurePermissions()) return;
    _running = true;

    // 1) Anunciar el servicio Proxi (solo el UUID → cabe en el paquete BLE de 31 bytes).
    try {
      await _peripheral.start(
        advertiseData: ble.AdvertiseData(
          serviceUuid: serviceGuid.str,
          includeDeviceName: false,
        ),
      );
    } catch (_) {/* algunos equipos no anuncian; el escaneo igual sirve si el otro sí anuncia */}

    // 2) Escanear al otro Proxi y quedarse con el más fuerte (2 personas).
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      ScanResult? best;
      for (final r in results) {
        final isProxi = r.advertisementData.serviceUuids
            .map((g) => g.str.toLowerCase())
            .contains(serviceGuid.str.toLowerCase());
        if (isProxi && (best == null || r.rssi > best.rssi)) best = r;
      }
      if (best != null) {
        _ema = (_ema ?? best.rssi.toDouble()) * 0.75 + best.rssi * 0.25;
        _controller.add(BleSample(_ema!.round(), _meters(_ema!)));
      }
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [serviceGuid],
        continuousUpdates: true,
        removeIfGone: const Duration(seconds: 6),
      );
    } catch (_) {}
  }

  // Path-loss simple: d = 10^((txPower - rssi)/(10*n)). Calibrar txPower/n en cancha.
  double _meters(double rssi) {
    const txPower = -59.0; // RSSI esperado a 1 m
    const n = 2.5; // exponente de pérdida (2 abierto, 3+ con cuerpos)
    return pow(10, (txPower - rssi) / (10 * n)).toDouble();
  }

  Future<void> stop() async {
    _running = false;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    try {
      await _peripheral.stop();
    } catch (_) {}
  }
}
