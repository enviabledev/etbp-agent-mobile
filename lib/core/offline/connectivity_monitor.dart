import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityMonitor {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription? _subscription;
  bool _isOnline = true;
  final List<VoidCallback> _onlineCallbacks = [];
  final List<VoidCallback> _offlineCallbacks = [];

  bool get isOnline => _isOnline;

  void start() {
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online != _isOnline) {
        _isOnline = online;
        if (online) {
          for (final cb in _onlineCallbacks) { cb(); }
        } else {
          for (final cb in _offlineCallbacks) { cb(); }
        }
      }
    });
  }

  void onOnline(VoidCallback callback) => _onlineCallbacks.add(callback);
  void onOffline(VoidCallback callback) => _offlineCallbacks.add(callback);

  void dispose() { _subscription?.cancel(); }
}
