class RawSensorReading {
  final int hr;
  final int hrValid;
  final int spo2;
  final int spo2Valid;
  final int ir;
  final int red;
  final int algoHr;
  final int instantHr;
  final int rateCount;
  final String status;

  const RawSensorReading({
    required this.hr,
    required this.hrValid,
    required this.spo2,
    required this.spo2Valid,
    required this.ir,
    required this.red,
    required this.algoHr,
    required this.instantHr,
    required this.rateCount,
    required this.status,
  });

  factory RawSensorReading.fromJson(Map<String, dynamic> json) {
    int readInt(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is double) return value.round();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return RawSensorReading(
      hr: readInt('hr'),
      hrValid: readInt('hr_valid'),
      spo2: readInt('spo2'),
      spo2Valid: readInt('spo2_valid'),
      ir: readInt('ir'),
      red: readInt('red'),
      algoHr: readInt('algo_hr'),
      instantHr: readInt('instant_hr'),
      rateCount: readInt('rate_count'),
      status: (json['status'] ?? 'measuring').toString(),
    );
  }
}

class ProcessedSensorReading {
  final int hr;
  final int spo2;
  final String sensorQuality;
  final String hrSource;
  final String hrQuality;
  final int rawHr;
  final int algoHr;
  final int instantHr;
  final int sourceHr;
  final int fixedHr;
  final int ir;
  final int red;

  const ProcessedSensorReading({
    required this.hr,
    required this.spo2,
    required this.sensorQuality,
    required this.hrSource,
    required this.hrQuality,
    required this.rawHr,
    required this.algoHr,
    required this.instantHr,
    required this.sourceHr,
    required this.fixedHr,
    required this.ir,
    required this.red,
  });

  static const empty = ProcessedSensorReading(
    hr: 0,
    spo2: 0,
    sensorQuality: 'WAITING',
    hrSource: 'none',
    hrQuality: 'waiting',
    rawHr: 0,
    algoHr: 0,
    instantHr: 0,
    sourceHr: 0,
    fixedHr: 0,
    ir: 0,
    red: 0,
  );
}
