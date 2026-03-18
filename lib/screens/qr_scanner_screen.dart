import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:etbp_agent_mobile/config/theme.dart';
import 'package:etbp_agent_mobile/core/auth/auth_provider.dart';
import 'package:etbp_agent_mobile/core/api/endpoints.dart';

class QRScannerScreen extends ConsumerStatefulWidget {
  const QRScannerScreen({super.key});
  @override
  ConsumerState<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends ConsumerState<QRScannerScreen> {
  final MobileScannerController _scanner = MobileScannerController();
  List<Map<String, dynamic>> _trips = [];
  String? _selectedTripId;
  String? _lastScanned;
  _ScanResult? _result;
  bool _processing = false;

  @override
  void initState() { super.initState(); _loadTrips(); }

  Future<void> _loadTrips() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get(Endpoints.agentTrips);
      setState(() => _trips = List<Map<String, dynamic>>.from(res.data['items'] ?? []));
      if (_trips.isNotEmpty) _selectedTripId = _trips[0]['id'];
    } catch (_) {}
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || _processing || code == _lastScanned || _selectedTripId == null) return;
    _lastScanned = code;
    setState(() => _processing = true);

    final bookingRef = code.replaceFirst(RegExp(r'^ETBP-', caseSensitive: false), '').trim().toUpperCase();

    try {
      final api = ref.read(apiClientProvider);
      // Lookup booking
      final bookingRes = await api.get(Endpoints.agentBookingLookup(bookingRef));
      final bookingId = bookingRes.data['id'];
      // Checkin
      final checkinRes = await api.post(Endpoints.agentCheckin(_selectedTripId!, bookingId));
      HapticFeedback.mediumImpact();
      setState(() => _result = _ScanResult('success', checkinRes.data['passenger_name'] ?? 'Checked in', 'Seat ${checkinRes.data['seat_number'] ?? '?'}'));
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('already')) { setState(() => _result = _ScanResult('already', 'Already checked in', bookingRef)); }
      else { setState(() => _result = _ScanResult('error', 'Check-in failed', msg.length > 60 ? msg.substring(0, 60) : msg)); }
    }

    setState(() => _processing = false);
    Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() { _result = null; _lastScanned = null; }); });
  }

  @override
  void dispose() { _scanner.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Scan Boarding Pass'),
      actions: [if (_trips.isNotEmpty) PopupMenuButton<String>(
        initialValue: _selectedTripId,
        onSelected: (id) => setState(() => _selectedTripId = id),
        itemBuilder: (_) => _trips.map((t) => PopupMenuItem(value: t['id'] as String, child: Text('${t['route_name']} ${(t['departure_time'] as String?)?.substring(0, 5) ?? ''}', style: const TextStyle(fontSize: 13)))).toList(),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [const Icon(Icons.directions_bus, size: 16, color: Colors.white), const SizedBox(width: 4), Text(_trips.firstWhere((t) => t['id'] == _selectedTripId, orElse: () => {'route_name': 'Select'})['route_name'] ?? 'Select', style: const TextStyle(color: Colors.white, fontSize: 13))])),
      )],
    ),
    body: Stack(children: [
      MobileScanner(controller: _scanner, onDetect: _onDetect),
      Center(child: Container(width: 250, height: 250, decoration: BoxDecoration(border: Border.all(color: AppTheme.primary, width: 3), borderRadius: BorderRadius.circular(16)))),
      if (_result != null) Positioned(bottom: 100, left: 24, right: 24, child: Container(
        padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: _result!.color, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(_result!.icon, color: Colors.white, size: 36), const SizedBox(height: 8),
          Text(_result!.message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
          if (_result!.detail != null) Text(_result!.detail!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      )),
    ]),
  );
}

class _ScanResult {
  final String type, message;
  final String? detail;
  _ScanResult(this.type, this.message, [this.detail]);
  Color get color => type == 'success' ? AppTheme.success : type == 'already' ? AppTheme.warning : AppTheme.error;
  IconData get icon => type == 'success' ? Icons.check_circle : type == 'already' ? Icons.info : Icons.cancel;
}
