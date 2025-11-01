import 'dart:async';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:logging/logging.dart';

/// A wrapper around Firebase Performance that gracefully handles cases where
/// Firebase is not available or not properly initialized.
class FirebasePerformanceWrapper {
  static final _log = Logger("FirebasePerformanceWrapper");
  static FirebasePerformance? _firebasePerformance;
  static bool _isInitialized = false;
  static bool _isAvailable = false;

  /// Initialize the wrapper. This should be called after Firebase.initializeApp()
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _firebasePerformance = FirebasePerformance.instance;
      _isAvailable = true;
      _log.info("Firebase Performance initialized successfully");
    } catch (e) {
      _log.warning("Firebase Performance not available: $e");
      _isAvailable = false;
    }
    
    _isInitialized = true;
  }

  /// Check if Firebase Performance is available
  static bool get isAvailable => _isAvailable && _firebasePerformance != null;

  /// Get a new HTTP metric trace, or null if Firebase is not available
  static HttpMetric? newHttpMetric(String url, HttpMethod httpMethod) {
    if (!isAvailable) return null;
    
    try {
      return _firebasePerformance!.newHttpMetric(url, httpMethod);
    } catch (e) {
      _log.warning("Failed to create HTTP metric: $e");
      return null;
    }
  }

  /// Get a new trace, or null if Firebase is not available
  static Trace? newTrace(String name) {
    if (!isAvailable) return null;
    
    try {
      return _firebasePerformance!.newTrace(name);
    } catch (e) {
      _log.warning("Failed to create trace: $e");
      return null;
    }
  }
}

/// A no-op implementation of HttpMetric for when Firebase is not available
class NoOpHttpMetric implements HttpMetric {
  @override
  int? httpResponseCode;

  @override
  int? requestPayloadSize;

  @override
  String? responseContentType;

  @override
  int? responsePayloadSize;

  String? url;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void putAttribute(String name, String value) {}

  @override
  void removeAttribute(String name) {}

  @override
  String? getAttribute(String name) => null;

  @override
  Map<String, String> getAttributes() => {};
}

/// A no-op implementation of Trace for when Firebase is not available
class NoOpTrace implements Trace {
  String get name => '';

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void putAttribute(String name, String value) {}

  @override
  void removeAttribute(String name) {}

  @override
  String? getAttribute(String name) => null;

  @override
  Map<String, String> getAttributes() => {};

  void putMetric(String metricName, int value) {}

  @override
  int getMetric(String metricName) => 0;

  @override
  void incrementMetric(String metricName, [int incrementBy = 1]) {}

  @override
  void setMetric(String metricName, int value) {}
}
