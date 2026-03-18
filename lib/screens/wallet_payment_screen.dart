import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:etbp_agent_mobile/config/theme.dart';
import 'package:etbp_agent_mobile/core/auth/auth_provider.dart';
import 'package:etbp_agent_mobile/core/api/endpoints.dart';

class WalletPaymentScreen extends ConsumerStatefulWidget {
  const WalletPaymentScreen({super.key});
  @override
  ConsumerState<WalletPaymentScreen> createState() => _WalletPaymentScreenState();
}

class _WalletPaymentScreenState extends ConsumerState<WalletPaymentScreen> {
  String _step = 'scan'; // scan, details, success
  String? _token;
  final _amountC = TextEditingController();
  final _descC = TextEditingController(text: 'Trip booking');
  bool _processing = false;
  Map<String, dynamic>? _result;
  MobileScannerController? _scanner;

  @override
  void initState() { super.initState(); _scanner = MobileScannerController(); }

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || !code.startsWith('ETBP-PAY:')) return;
    _token = code.replaceFirst('ETBP-PAY:', '');
    _scanner?.stop();
    setState(() => _step = 'details');
  }

  Future<void> _process() async {
    final amount = double.tryParse(_amountC.text);
    if (amount == null || amount <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount'))); return; }
    setState(() => _processing = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post(Endpoints.walletPayment, data: {'token': _token, 'amount': amount, 'description': _descC.text.trim()});
      setState(() { _result = res.data; _step = 'success'; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error));
    } finally { if (mounted) setState(() => _processing = false); }
  }

  void _reset() {
    _token = null; _amountC.clear(); _result = null;
    _scanner = MobileScannerController();
    setState(() => _step = 'scan');
  }

  @override
  void dispose() { _scanner?.dispose(); _amountC.dispose(); _descC.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_step == 'success') return Scaffold(
      appBar: AppBar(title: const Text('Payment Complete')),
      body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle, size: 64, color: AppTheme.success),
        const SizedBox(height: 16),
        Text('₦${(_result?['amount_debited'] ?? 0).toLocaleString()}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Debited from ${_result?['customer_name'] ?? 'customer'}', style: const TextStyle(color: AppTheme.textSecondary)),
        Text('New balance: ₦${(_result?['new_balance'] ?? 0).toLocaleString()}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 32),
        ElevatedButton(onPressed: _reset, child: const Text('Process Another')),
      ]))),
    );

    if (_step == 'details') return Scaffold(
      appBar: AppBar(title: const Text('Payment Details')),
      body: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: const Row(children: [Icon(Icons.check_circle, color: AppTheme.success), SizedBox(width: 8), Text('Token captured', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600))])),
        const SizedBox(height: 24),
        TextFormField(controller: _amountC, decoration: const InputDecoration(labelText: 'Amount (₦)', prefixText: '₦ '), keyboardType: TextInputType.number, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextFormField(controller: _descC, decoration: const InputDecoration(labelText: 'Description')),
        const SizedBox(height: 32),
        ElevatedButton(onPressed: _processing ? null : _process, child: _processing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Process Payment')),
      ])),
    );

    // Scan step
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Scan Wallet QR')),
      body: Stack(children: [
        if (_scanner != null) MobileScanner(controller: _scanner!, onDetect: _onDetect),
        Center(child: Container(width: 250, height: 250, decoration: BoxDecoration(border: Border.all(color: AppTheme.success, width: 3), borderRadius: BorderRadius.circular(16)))),
        const Positioned(bottom: 60, left: 0, right: 0, child: Text('Point camera at customer\'s wallet QR code', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 14))),
      ]),
    );
  }
}
