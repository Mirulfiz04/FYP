import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/sensor_reading.dart';
import 'sensor_config.dart';
import 'sensor_service.dart';

/// Bluetooth-LE backend for the ESP32 heart-rate sensor.
///
/// Why this exists: with the Wi-Fi SoftAP transport the phone has to JOIN the
/// ESP32 hotspot, which knocks it off the internet — hence the "mobile data on +
/// Wi-Fi-pinned fetch" workaround. BLE runs alongside normal Wi-Fi, so the phone
/// keeps its internet (Supabase + Gemini) AND reads the sensor at the same time.
///
/// It is a singleton because a BLE connection is stateful and long-lived: we
/// scan + connect once, subscribe to the data characteristic, and cache the most
/// recent notification. [fetchReading] just hands back that cache, so the
/// existing pull-based polling loops keep working unchanged.
///
/// GATT contract — must match the ESP32 NimBLE firmware
/// (emotion_detection_system_ble.ino):
///   service        fff0
///   data char      fff1  (NOTIFY + READ, JSON identical to the Wi-Fi /data body)
///
/// Note: BLE does NOT work on the standard Android emulator — test on a physical
/// phone over USB.
class BleSensorService implements SensorService {
  BleSensorService._();
  static final BleSensorService instance = BleSensorService._();

  /// Advertised name of the ESP32. Matched during scanning.
  static const String deviceName = 'MEDS_ESP32';

  static final Guid serviceUuid =
      Guid('0000fff0-0000-1000-8000-00805f9b34fb');
  static final Guid dataCharUuid =
      Guid('0000fff1-0000-1000-8000-00805f9b34fb');

  /// A cached reading older than this is treated as "no data" so callers fall
  /// back to their disconnected path (same behaviour as a Wi-Fi timeout).
  static const Duration _staleAfter = Duration(seconds: 5);
  static const Duration _scanTimeout = Duration(seconds: 8);
  static const Duration _readTimeout = Duration(seconds: 6);

  final StreamController<RawSensorReading> _readings =
      StreamController<RawSensorReading>.broadcast();

  // --- Debug surface (for hardware bring-up; see the Settings BLE panel) -----
  final StreamController<String> _rawFrames =
      StreamController<String>.broadcast();
  final StreamController<bool> _connState = StreamController<bool>.broadcast();

  /// Decoded text of every notification, malformed frames included — so a
  /// truncated frame (e.g. MTU too small) is visible rather than silently
  /// dropped.
  Stream<String> get rawFrames => _rawFrames.stream;

  /// Emits true on connect, false on disconnect.
  Stream<bool> get connectionState => _connState.stream;

  /// Total notifications received this session, and the most recent raw frame.
  int framesReceived = 0;
  String? lastRawFrame;
  DateTime? get lastFrameAt => _latestAt;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _dataChar;
  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  RawSensorReading? _latest;
  DateTime? _latestAt;
  Future<void>? _connecting;

  bool get isConnected =>
      _device != null && _device!.isConnected && _dataChar != null;

  String? get connectedDeviceName => _device?.platformName;
  String? get connectedDeviceId => _device?.remoteId.str;

  @override
  Future<RawSensorReading> fetchReading() async {
    if (!isConnected) await connect();

    final cached = _latest;
    final at = _latestAt;
    final fresh = cached != null &&
        at != null &&
        DateTime.now().difference(at) <= _staleAfter;
    if (fresh) return cached;

    // No fresh cache yet — wait for the next notification frame.
    return _readings.stream.first.timeout(
      _readTimeout,
      onTimeout: () =>
          throw TimeoutException('BLE: no sensor notification in time'),
    );
  }

  /// Scans for [deviceName], connects, and subscribes to the data
  /// characteristic. Concurrent callers share a single in-flight attempt.
  Future<void> connect() {
    if (isConnected) return Future.value();
    return _connecting ??=
        _doConnect().whenComplete(() => _connecting = null);
  }

  Future<void> _doConnect() async {
    if (!await FlutterBluePlus.isSupported) {
      throw Exception('Bluetooth is not available on this device '
          '(BLE does not work on the emulator).');
    }
    await _ensurePermissions();

    // Best-effort: turn the adapter on (Android only).
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on &&
        Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {/* user may decline; startScan will surface the error */}
    }

    final device = await _scanForDevice();
    if (device == null) {
      throw Exception('Could not find "$deviceName". Make sure the ESP32 is '
          'powered and advertising.');
    }

    _connSub?.cancel();
    _connSub = device.connectionState.listen((s) {
      final connected = s == BluetoothConnectionState.connected;
      if (s == BluetoothConnectionState.disconnected) {
        _dataChar = null;
      }
      if (!_connState.isClosed) _connState.add(connected);
    });

    await device.connect(timeout: _scanTimeout, autoConnect: false);
    _device = device;

    // Bigger MTU so the ~160-byte JSON frame fits in a single notification.
    if (Platform.isAndroid) {
      try {
        await device.requestMtu(247);
      } catch (_) {/* non-fatal; firmware also keeps the payload small */}
    }

    await _subscribe(device);
  }

  Future<BluetoothDevice?> _scanForDevice() async {
    final completer = Completer<BluetoothDevice?>();
    final savedId = sensorConfig.bleDeviceId;

    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final adv = r.advertisementData;
        final matches = r.device.platformName == deviceName ||
            adv.advName == deviceName ||
            (savedId != null && r.device.remoteId.str == savedId) ||
            adv.serviceUuids.contains(serviceUuid);
        if (matches && !completer.isCompleted) {
          completer.complete(r.device);
        }
      }
    });

    // Scan unfiltered and match in the callback: more robust than a
    // service-UUID filter if the ESP32 puts the UUID in the scan response.
    await FlutterBluePlus.startScan(timeout: _scanTimeout);

    return completer.future
        .timeout(_scanTimeout, onTimeout: () => null)
        .whenComplete(() async {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    });
  }

  Future<void> _subscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();
    BluetoothCharacteristic? dataChar;
    for (final s in services) {
      if (s.uuid == serviceUuid) {
        for (final c in s.characteristics) {
          if (c.uuid == dataCharUuid) dataChar = c;
        }
      }
    }
    if (dataChar == null) {
      throw Exception('BLE: data characteristic (fff1) not found on the device');
    }
    _dataChar = dataChar;

    _valueSub?.cancel();
    _valueSub = dataChar.onValueReceived.listen(_onValue);
    await dataChar.setNotifyValue(true);

    // Prime the cache with one read so fetchReading can return immediately.
    try {
      _onValue(await dataChar.read());
    } catch (_) {/* the first notification will fill the cache shortly */}
  }

  void _onValue(List<int> bytes) {
    if (bytes.isEmpty) return;
    final raw = utf8.decode(bytes, allowMalformed: true);
    lastRawFrame = raw;
    framesReceived++;
    if (!_rawFrames.isClosed) _rawFrames.add(raw);
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      final reading = RawSensorReading.fromJson(map);
      _latest = reading;
      _latestAt = DateTime.now();
      if (!_readings.isClosed) _readings.add(reading);
    } catch (_) {/* malformed/truncated frame — still shown in the debug panel */}
  }

  Future<void> _ensurePermissions() async {
    if (!Platform.isAndroid) return;
    final scan = await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    // bluetoothScan is only meaningful on Android 12+. If it isn't granted here
    // we're likely on Android 11 or below, where BLE scanning needs location.
    if (!scan.isGranted) {
      await Permission.locationWhenInUse.request();
    }
  }

  Future<void> disconnect() async {
    await _valueSub?.cancel();
    _valueSub = null;
    await _connSub?.cancel();
    _connSub = null;
    try {
      await _device?.disconnect();
    } catch (_) {/* ignore */}
    _device = null;
    _dataChar = null;
    _latest = null;
    _latestAt = null;
    if (!_connState.isClosed) _connState.add(false);
  }
}
