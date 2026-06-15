import 'dart:collection';
import '../models/sensor_reading.dart';

class SensorFilter {
  static const int hrMin = 45;
  static const int hrMax = 120;
  static const int hrCalibrationOffset = 0;
  static const int hrHistorySize = 10;
  static const int spo2HistorySize = 8;
  static const int signalHistorySize = 10;
  static const int hrJumpLimit = 15;
  static const int hrInitJumpLimit = 18;
  static const double signalShiftRatio = 0.15;

  final Queue<int> _hrHistory = Queue<int>();
  final Queue<int> _spo2History = Queue<int>();
  final Queue<int> _irHistory = Queue<int>();
  final Queue<int> _redHistory = Queue<int>();

  int _hrDisplay = 0;
  int _spo2Display = 0;
  String _sensorQuality = 'WAITING';

  ProcessedSensorReading process(RawSensorReading raw) {
    final choice = _chooseBestHr(raw);
    final sourceHr = choice.hr;
    final hrSource = choice.source;
    final sourceValid = choice.valid;

    final fixedHr = _fixPossibleDoubleHr(sourceHr);
    final calibratedHr = _applyCalibration(fixedHr);
    final signalOk = _isSignalStable(raw.ir, raw.red);

    final acceptedHr = sourceValid &&
        signalOk &&
        calibratedHr >= hrMin &&
        calibratedHr <= hrMax &&
        _isHrStableEnough(calibratedHr);

    if (acceptedHr) {
      _addLimited(_hrHistory, calibratedHr, hrHistorySize);
      _hrDisplay = _smoothHr();
    }

    if (raw.spo2Valid == 1 && raw.spo2 >= 85 && raw.spo2 <= 100) {
      _addLimited(_spo2History, raw.spo2, spo2HistorySize);
      _spo2Display = _smoothSpo2();
    }

    _updateSignalHistory(raw.ir, raw.red);
    final hrQuality = _getHrQuality(raw, sourceHr, fixedHr, calibratedHr, acceptedHr, signalOk, hrSource);
    _updateSensorQuality(raw, acceptedHr, sourceHr);

    return ProcessedSensorReading(
      hr: _hrDisplay,
      spo2: _spo2Display,
      sensorQuality: _sensorQuality,
      hrSource: hrSource,
      hrQuality: hrQuality,
      rawHr: raw.hr,
      algoHr: raw.algoHr,
      instantHr: raw.instantHr,
      sourceHr: sourceHr,
      fixedHr: fixedHr,
      ir: raw.ir,
      red: raw.red,
    );
  }

  _HrChoice _chooseBestHr(RawSensorReading raw) {
    if (raw.hrValid == 1 && raw.hr >= hrMin && raw.hr <= hrMax) {
      return _HrChoice(raw.hr, true, 'main');
    }

    if (raw.algoHr >= hrMin && raw.algoHr <= 160) {
      return _HrChoice(raw.algoHr, true, 'algo_backup');
    }

    if (raw.rateCount > 0 && raw.instantHr >= hrMin && raw.instantHr <= 160) {
      return _HrChoice(raw.instantHr, true, 'instant_backup');
    }

    return _HrChoice(0, false, 'none');
  }

  int _fixPossibleDoubleHr(int hr) {
    if (hr <= 0) return 0;

    if (hr >= 120) {
      final half = hr ~/ 2;
      final calibratedHalf = _applyCalibration(half);

      if (_hrHistory.length >= 2) {
        final recent = _smoothHr();
        if (calibratedHalf > 0 && (calibratedHalf - recent).abs() <= 12) {
          return half;
        }
      }

      if (_hrHistory.isEmpty && half >= 55 && half <= 95) {
        return half;
      }

      return 0;
    }

    return hr;
  }

  int _applyCalibration(int hr) {
    if (hr <= 0) return 0;
    final calibrated = hr + hrCalibrationOffset;
    if (calibrated >= hrMin && calibrated <= hrMax) return calibrated;
    return 0;
  }

  bool _isHrStableEnough(int calibratedHr) {
    if (calibratedHr <= 0) return false;
    if (_hrHistory.isEmpty) return calibratedHr >= 50 && calibratedHr <= 100;

    final recent = _smoothHr();
    final difference = (calibratedHr - recent).abs();

    if (_hrHistory.length < 4) return difference <= hrInitJumpLimit;
    return difference <= hrJumpLimit;
  }

  bool _isSignalStable(int ir, int red) {
    if (ir <= 0 || red <= 0) return false;
    if (_irHistory.length < 5 || _redHistory.length < 5) return true;

    final medianIr = _median(_irHistory.toList());
    final medianRed = _median(_redHistory.toList());
    if (medianIr <= 0 || medianRed <= 0) return true;

    final irChange = (ir - medianIr).abs() / medianIr;
    final redChange = (red - medianRed).abs() / medianRed;

    return irChange <= signalShiftRatio && redChange <= signalShiftRatio;
  }

  void _updateSignalHistory(int ir, int red) {
    if (ir > 0 && red > 0) {
      _addLimited(_irHistory, ir, signalHistorySize);
      _addLimited(_redHistory, red, signalHistorySize);
    }
  }

  void _updateSensorQuality(RawSensorReading raw, bool acceptedHr, int sourceHr) {
    final spo2Ok = raw.spo2Valid == 1 && raw.spo2 >= 85 && raw.spo2 <= 100;
    final hasPreviousHr = _hrDisplay > 0;

    if (raw.status == 'no_finger') {
      _sensorQuality = 'NO FINGER';
    } else if (acceptedHr) {
      _sensorQuality = 'GOOD';
    } else if (hasPreviousHr && spo2Ok) {
      _sensorQuality = 'HOLDING HR';
    } else if (hasPreviousHr && sourceHr == 0) {
      _sensorQuality = 'HOLDING HR';
    } else {
      _sensorQuality = 'BAD SIGNAL';
    }
  }

  String _getHrQuality(
    RawSensorReading raw,
    int sourceHr,
    int fixedHr,
    int calibratedHr,
    bool accepted,
    bool signalOk,
    String hrSource,
  ) {
    if (accepted) return 'stable';
    if (_hrDisplay > 0 && sourceHr == 0) return 'hold_last_hr';
    if (sourceHr == 0) return 'no_hr_source';
    if (raw.hr == 0 && hrSource != 'none') return 'using_backup';
    if (!signalOk) return 'signal_shift';
    if (sourceHr >= 120 && fixedHr == 0) return 'spike_filtered';
    if (calibratedHr == 0) return 'out_of_range';
    return 'filtered_jump';
  }

  int _smoothHr() {
    if (_hrHistory.isEmpty) return 0;
    final values = _hrHistory.toList();
    final median = _median(values);
    final clean = values.where((v) => (v - median).abs() <= 10).toList();
    final usable = clean.isEmpty ? values : clean;
    return (usable.reduce((a, b) => a + b) / usable.length).round();
  }

  int _smoothSpo2() {
    if (_spo2History.isEmpty) return 0;
    final values = _spo2History.where((v) => v >= 85 && v <= 100).toList();
    if (values.isEmpty) return 0;
    return (values.reduce((a, b) => a + b) / values.length).round();
  }

  int _median(List<int> values) {
    if (values.isEmpty) return 0;
    values.sort();
    return values[values.length ~/ 2];
  }

  void _addLimited(Queue<int> queue, int value, int maxLength) {
    queue.addLast(value);
    while (queue.length > maxLength) {
      queue.removeFirst();
    }
  }
}

class _HrChoice {
  final int hr;
  final bool valid;
  final String source;

  const _HrChoice(this.hr, this.valid, this.source);
}
