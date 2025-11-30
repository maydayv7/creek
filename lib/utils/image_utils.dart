// lib/utils/image_utils.dart

import 'dart:math';

List<double> l2Normalize(List<double> vec) {
  double sum = vec.fold(0, (p, c) => p + c * c);
  double norm = sqrt(sum);
  if (norm == 0) return vec;
  return vec.map((v) => v / norm).toList();
}

double dotProduct(List<double> a, List<double> b) {
  double sum = 0;
  // Ensure lengths match to avoid range errors
  int len = min(a.length, b.length);
  for (int i = 0; i < len; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

double cosineSim(List<double> a, List<double> b) {
  double dot = 0.0, nA = 0.0, nB = 0.0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    nA += a[i] * a[i];
    nB += b[i] * b[i];
  }
  return (nA == 0 || nB == 0) ? 0.0 : dot / (sqrt(nA) * sqrt(nB));
}
