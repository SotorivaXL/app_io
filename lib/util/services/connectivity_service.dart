import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  // Singleton pattern
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final StreamController<List<ConnectivityResult>> _controller =
  StreamController<List<ConnectivityResult>>.broadcast();

  Stream<List<ConnectivityResult>> get connectivityStream => _controller.stream;

  void initialize() {
    _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      _controller.add(results);
    });
  }

  Future<List<ConnectivityResult>> checkConnectivity() async {
    List<ConnectivityResult> results = await _connectivity.checkConnectivity();
    return results;
  }

  void dispose() {
    _controller.close();
  }
}
