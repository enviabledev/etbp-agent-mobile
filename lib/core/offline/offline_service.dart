import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class AgentOfflineService {
  static Database? _db;

  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/etbp_agent_offline.db';
    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('CREATE TABLE cached_trips (trip_id TEXT PRIMARY KEY, data TEXT, cached_at TEXT)');
      await db.execute('CREATE TABLE cached_manifests (trip_id TEXT PRIMARY KEY, data TEXT, cached_at TEXT)');
      await db.execute('CREATE TABLE action_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, payload TEXT, created_at TEXT, synced INTEGER DEFAULT 0)');
    });
    return _db!;
  }

  Future<void> cacheTrips(List<Map<String, dynamic>> trips) async {
    final db = await _getDb();
    for (final trip in trips) {
      await db.insert('cached_trips', {'trip_id': trip['id'] ?? '', 'data': jsonEncode(trip), 'cached_at': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<Map<String, dynamic>>> getCachedTrips() async {
    final db = await _getDb();
    final results = await db.query('cached_trips');
    return results.map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>).toList();
  }

  Future<void> queueAction(String type, Map<String, dynamic> payload) async {
    final db = await _getDb();
    await db.insert('action_queue', {'type': type, 'payload': jsonEncode(payload), 'created_at': DateTime.now().toIso8601String(), 'synced': 0});
    debugPrint('Offline: queued action $type');
  }

  Future<int> pendingActionCount() async {
    final db = await _getDb();
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM action_queue WHERE synced = 0');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> syncQueue(dynamic api) async {
    final db = await _getDb();
    final pending = await db.query('action_queue', where: 'synced = 0', orderBy: 'created_at ASC');
    for (final action in pending) {
      try {
        final type = action['type'] as String;
        final payload = jsonDecode(action['payload'] as String) as Map<String, dynamic>;
        switch (type) {
          case 'checkin':
            await api.post('/agent/trips/${payload['trip_id']}/checkin/${payload['booking_id']}');
          case 'payment':
            await api.post('/agent/bookings/${payload['booking_ref']}/pay', data: payload['data']);
        }
        await db.update('action_queue', {'synced': 1}, where: 'id = ?', whereArgs: [action['id']]);
      } catch (e) {
        debugPrint('Offline: sync failed: $e');
        break;
      }
    }
  }
}
