import 'dart:typed_data';

/// YIN 音高检测。输入 [-1,1] 归一化采样，返回 Hz 或 null（未检测到周期性）。
double? detectPitch(List<double> buf, int sampleRate, {double threshold = 0.15}) {
  final n = buf.length;
  if (n < 512) return null;
  final half = n ~/ 2;
  final diff = Float64List(half);
  for (var tau = 1; tau < half; tau++) {
    var sum = 0.0;
    for (var i = 0; i < half; i++) {
      final d = buf[i] - buf[i + tau];
      sum += d * d;
    }
    diff[tau] = sum;
  }
  final cmnd = Float64List(half);
  var running = 0.0;
  for (var tau = 1; tau < half; tau++) {
    running += diff[tau];
    cmnd[tau] = running == 0 ? double.nan : diff[tau] * tau / running;
  }
  var tauEst = -1;
  for (var tau = 2; tau < half - 1; tau++) {
    if (cmnd[tau] < threshold) {
      while (tau + 1 < half - 1 && cmnd[tau + 1] < cmnd[tau]) {
        tau++;
      }
      tauEst = tau;
      break;
    }
  }
  if (tauEst < 0) return null;
  final x0 = tauEst > 1 ? cmnd[tauEst - 1] : cmnd[tauEst];
  final x1 = cmnd[tauEst];
  final x2 = cmnd[tauEst + 1];
  final denom = 2 * (2 * x1 - x2 - x0);
  final better = denom == 0 ? tauEst.toDouble() : tauEst + (x2 - x0) / denom;
  if (better <= 0) return null;
  return sampleRate / better;
}
