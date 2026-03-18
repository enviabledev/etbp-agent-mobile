import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import 'package:etbp_agent_mobile/config/theme.dart';
import 'package:etbp_agent_mobile/core/auth/auth_provider.dart';
import 'package:etbp_agent_mobile/core/api/endpoints.dart';

class QRScannerScreen extends ConsumerStatefulWidget {
  const QRScannerScreen({super.key});
  @override
  ConsumerState<QRScannerScreen> createState() => _QRScannerScreenState();
}

enum _ScanMode { boarding, walletQR }

class _QRScannerScreenState extends ConsumerState<QRScannerScreen> {
  final MobileScannerController _scanner = MobileScannerController();
  _ScanMode _mode = _ScanMode.boarding;
  String? _lastScanned;
  bool _processing = false;
  bool _sheetOpen = false;

  // Wallet QR sub-mode: pending booking context
  Map<String, dynamic>? _pendingBookingForPayment;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || _processing || _sheetOpen) return;
    if (code == _lastScanned) return;
    _lastScanned = code;

    if (_mode == _ScanMode.walletQR) {
      await _handleWalletQR(code);
      return;
    }

    // Boarding pass mode
    final bookingRef = code
        .replaceFirst(RegExp(r'^ETBP-', caseSensitive: false), '')
        .trim()
        .toUpperCase();
    if (bookingRef.isEmpty) return;

    setState(() => _processing = true);

    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get(Endpoints.agentBookingScan(bookingRef));
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() => _processing = false);
        _showBookingSheet(res.data);
      }
    } catch (e) {
      setState(() => _processing = false);
      final msg = e.toString();
      if (msg.contains('not found') || msg.contains('404')) {
        _showErrorSnack('Booking not found for reference: $bookingRef');
      } else {
        _showErrorSnack('Scan failed: ${msg.length > 80 ? msg.substring(0, 80) : msg}');
      }
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _lastScanned = null;
      });
    }
  }

  void _showErrorSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
    );
  }

  // ── Wallet QR sub-mode ──

  Future<void> _handleWalletQR(String code) async {
    if (!code.startsWith('ETBP-PAY:')) {
      _showErrorSnack('Not a wallet QR code. Looking for ETBP-PAY: prefix.');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _lastScanned = null;
      });
      return;
    }

    final token = code.replaceFirst('ETBP-PAY:', '');
    final pending = _pendingBookingForPayment;
    if (pending == null) return;

    setState(() => _processing = true);

    try {
      final api = ref.read(apiClientProvider);
      final amount = (pending['booking']?['total_amount'] ?? 0).toDouble();
      final bookingId = pending['booking']?['id'];
      await api.post(Endpoints.walletPayment, data: {
        'token': token,
        'amount': amount,
        'description': 'Booking ${pending['booking']?['reference'] ?? ''}',
        'booking_id': bookingId,
      });

      HapticFeedback.heavyImpact();

      // Payment successful — re-fetch booking and show updated sheet
      final bookingRef = pending['booking']?['reference'] ?? '';
      final res = await api.get(Endpoints.agentBookingScan(bookingRef));

      setState(() {
        _processing = false;
        _mode = _ScanMode.boarding;
        _pendingBookingForPayment = null;
      });

      if (mounted) _showBookingSheet(res.data);
    } catch (e) {
      setState(() => _processing = false);
      _showErrorSnack('Wallet payment failed: ${e.toString().length > 60 ? e.toString().substring(0, 60) : e}');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _lastScanned = null;
      });
    }
  }

  void _switchToWalletMode(Map<String, dynamic> bookingData) {
    setState(() {
      _mode = _ScanMode.walletQR;
      _pendingBookingForPayment = bookingData;
      _lastScanned = null;
      _sheetOpen = false;
    });
  }

  void _cancelWalletMode() {
    setState(() {
      _mode = _ScanMode.boarding;
      _pendingBookingForPayment = null;
      _lastScanned = null;
    });
  }

  // ── Bottom sheet ──

  void _showBookingSheet(Map<String, dynamic> data) {
    setState(() => _sheetOpen = true);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => _BookingActionSheet(
        data: data,
        onCheckIn: () => _performCheckIn(data),
        onPayCash: () => _performPayment(data, 'cash'),
        onPayPOS: () => _showPOSInput(data),
        onPayWalletQR: () {
          Navigator.pop(context);
          _switchToWalletMode(data);
        },
        onDismiss: () => Navigator.pop(context),
      ),
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _sheetOpen = false;
          _lastScanned = null;
        });
      }
    });
  }

  Future<void> _performCheckIn(Map<String, dynamic> data) async {
    final tripId = data['trip']?['id'];
    final bookingId = data['booking']?['id'];
    if (tripId == null || bookingId == null) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.post(Endpoints.agentCheckin(tripId, bookingId));
      HapticFeedback.heavyImpact();
      if (mounted) {
        Navigator.pop(context); // Close sheet
        _showSuccessOverlay(data);
      }
    } catch (e) {
      _showErrorSnack('Check-in failed: $e');
    }
  }

  Future<void> _performPayment(Map<String, dynamic> data, String method, [String? reference]) async {
    final bookingRef = data['booking']?['reference'] ?? '';

    try {
      final api = ref.read(apiClientProvider);
      await api.post(Endpoints.agentBookingPay(bookingRef), data: {
        'payment_method': method,
        if (reference != null) 'payment_reference': reference,
      });
      HapticFeedback.heavyImpact();

      // Re-fetch and show updated sheet
      final res = await api.get(Endpoints.agentBookingScan(bookingRef));
      if (mounted) {
        Navigator.pop(context); // Close current sheet
        _showBookingSheet(res.data); // Reopen with fresh data
      }
    } catch (e) {
      _showErrorSnack('Payment failed: $e');
    }
  }

  void _showPOSInput(Map<String, dynamic> data) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('POS Reference'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter POS transaction reference',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performPayment(data, 'pos', controller.text.trim());
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showSuccessOverlay(Map<String, dynamic> data) {
    final passengers = data['passengers'] as List? ?? [];
    final names = passengers.map((p) => p['name'] ?? '').join(', ');

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      pageBuilder: (_, __, ___) => Material(
        color: AppTheme.success,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 80),
                const SizedBox(height: 16),
                const Text('Checked In!', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(names, style: const TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
                Text(
                  passengers.map((p) => 'Seat ${p['seat_number'] ?? '?'}').join(', '),
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pop(context); // Remove overlay
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWalletMode = _mode == _ScanMode.walletQR;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: isWalletMode ? AppTheme.success : Colors.black,
        foregroundColor: Colors.white,
        title: Text(isWalletMode ? 'Scan Wallet Payment QR' : 'Scan Boarding Pass'),
        actions: isWalletMode
            ? [
                TextButton(
                  onPressed: _cancelWalletMode,
                  child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                ),
              ]
            : null,
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _scanner, onDetect: _onDetect),

          // Scan frame
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: isWalletMode ? AppTheme.success : AppTheme.primary,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Wallet mode banner
          if (isWalletMode)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: AppTheme.success.withValues(alpha: 0.9),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Point camera at customer\'s wallet QR to pay ₦${_formatAmount(_pendingBookingForPayment?['booking']?['total_amount'])}',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom hint
          if (!isWalletMode)
            const Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Text(
                'Point camera at boarding pass QR code',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),

          // Processing indicator
          if (_processing)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
        ],
      ),
    );
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '0';
    final num val = amount is num ? amount : double.tryParse(amount.toString()) ?? 0;
    return NumberFormat('#,##0', 'en_US').format(val);
  }
}

// ── Smart Action Bottom Sheet ──

class _BookingActionSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onCheckIn;
  final VoidCallback onPayCash;
  final VoidCallback onPayPOS;
  final VoidCallback onPayWalletQR;
  final VoidCallback onDismiss;

  const _BookingActionSheet({
    required this.data,
    required this.onCheckIn,
    required this.onPayCash,
    required this.onPayPOS,
    required this.onPayWalletQR,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final booking = data['booking'] as Map<String, dynamic>? ?? {};
    final trip = data['trip'] as Map<String, dynamic>? ?? {};
    final passengers = data['passengers'] as List? ?? [];
    final customer = data['customer'] as Map<String, dynamic>? ?? {};
    final actions = data['actions'] as Map<String, dynamic>? ?? {};

    final status = booking['status'] ?? '';
    final paymentStatus = booking['payment_status'] ?? '';
    final blockedReason = actions['check_in_blocked_reason'];
    final canCheckIn = actions['can_check_in'] == true;
    final canCollect = actions['can_collect_payment'] == true;
    final amountDue = actions['amount_due'] ?? 0;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            _buildHeader(booking, trip, passengers, customer),

            const SizedBox(height: 16),

            // Scenario-based content
            if (canCheckIn)
              _buildCheckInSection(passengers)
            else if (blockedReason == 'payment_required')
              _buildPaymentRequired(amountDue, canCheckIn)
            else if (blockedReason == 'trip_not_today')
              _buildTripNotToday(actions, canCollect, amountDue, paymentStatus)
            else if (blockedReason == 'already_checked_in')
              _buildAlreadyCheckedIn(passengers)
            else if (blockedReason == 'booking_expired')
              _buildExpired()
            else if (blockedReason == 'booking_cancelled')
              _buildCancelled(booking)
            else if (blockedReason == 'trip_departed' || blockedReason == 'trip_completed')
              _buildTripGone(blockedReason!, trip)
            else if (blockedReason == 'wrong_terminal')
              _buildWrongTerminal(actions),

            const SizedBox(height: 20),
            _closeButton(),
          ],
        ),
      ),
    );
  }

  // ── Header ──

  Widget _buildHeader(
    Map<String, dynamic> booking,
    Map<String, dynamic> trip,
    List passengers,
    Map<String, dynamic> customer,
  ) {
    final ref = booking['reference'] ?? '';
    final routeName = trip['route_name'] ?? '';
    final depDate = trip['departure_date'] ?? '';
    final depTime = trip['departure_time'] ?? '';
    final status = booking['status'] ?? '';

    String formattedDate = '';
    if (depDate.isNotEmpty) {
      try {
        final d = DateTime.parse(depDate);
        formattedDate = DateFormat('EEE, d MMM yyyy').format(d);
      } catch (_) {
        formattedDate = depDate;
      }
    }
    String formattedTime = '';
    if (depTime.length >= 5) {
      try {
        final parts = depTime.split(':');
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final dt = DateTime(2000, 1, 1, h, m);
        formattedTime = DateFormat('hh:mm a').format(dt);
      } catch (_) {
        formattedTime = depTime.substring(0, 5);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reference + Status
        Row(
          children: [
            Text(ref, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const Spacer(),
            _statusBadge(status),
          ],
        ),
        const SizedBox(height: 8),

        // Route
        if (routeName.isNotEmpty)
          Text(routeName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),

        // Date + Time
        if (formattedDate.isNotEmpty || formattedTime.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [formattedDate, formattedTime].where((s) => s.isNotEmpty).join(' • '),
              style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ),

        // Passengers
        if (passengers.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...passengers.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (p['checked_in'] == true) ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.border,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    p['seat_number'] ?? '?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: (p['checked_in'] == true) ? AppTheme.success : AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(p['name'] ?? '', style: const TextStyle(fontSize: 14)),
                if (p['checked_in'] == true) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check_circle, size: 16, color: AppTheme.success),
                ],
              ],
            ),
          )),
        ],

        // Customer
        if (customer['phone'] != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.phone, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Text(customer['phone'], style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _statusBadge(String status) {
    Color bg;
    Color fg;
    switch (status) {
      case 'confirmed':
        bg = AppTheme.primary.withValues(alpha: 0.1);
        fg = AppTheme.primary;
        break;
      case 'checked_in':
        bg = AppTheme.success.withValues(alpha: 0.1);
        fg = AppTheme.success;
        break;
      case 'pending':
        bg = AppTheme.warning.withValues(alpha: 0.1);
        fg = AppTheme.warning;
        break;
      case 'cancelled':
      case 'expired':
        bg = AppTheme.error.withValues(alpha: 0.1);
        fg = AppTheme.error;
        break;
      default:
        bg = Colors.grey[100]!;
        fg = Colors.grey[600]!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  // ── Scenario A: Ready to check in ──

  Widget _buildCheckInSection(List passengers) {
    final unchecked = passengers.where((p) => p['checked_in'] != true).toList();
    final someChecked = passengers.length != unchecked.length;

    return Column(
      children: [
        _banner(Icons.check_circle_outline, AppTheme.success, 'Ready for check-in', null),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: onCheckIn,
            icon: const Icon(Icons.check_circle, color: Colors.white),
            label: Text(
              someChecked
                  ? 'Check In Remaining (${unchecked.length})'
                  : 'Check In All Passengers (${passengers.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Scenario B: Payment required ──

  Widget _buildPaymentRequired(dynamic amountDue, bool canCheckInAfter) {
    return Column(
      children: [
        _banner(Icons.payment, AppTheme.warning, 'Payment Required', '₦${_fmtAmount(amountDue)}'),
        const SizedBox(height: 16),
        _paymentButtons(),
      ],
    );
  }

  Widget _paymentButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionButton(Icons.money, 'Cash', AppTheme.success, onPayCash),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _actionButton(Icons.credit_card, 'POS', AppTheme.primary, onPayPOS),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: _actionButton(Icons.qr_code_scanner, 'Wallet QR', const Color(0xFF7C3AED), onPayWalletQR),
        ),
      ],
    );
  }

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color, size: 22),
        label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 15)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // ── Scenario C: Trip not today ──

  Widget _buildTripNotToday(Map<String, dynamic> actions, bool canCollect, dynamic amountDue, String paymentStatus) {
    final availFrom = actions['check_in_available_from'] ?? '';
    String checkinOpens = '';
    if (availFrom.isNotEmpty) {
      try {
        final dt = DateTime.parse(availFrom);
        checkinOpens = DateFormat('EEE, d MMM • hh:mm a').format(dt);
      } catch (_) {
        checkinOpens = availFrom;
      }
    }

    return Column(
      children: [
        _banner(Icons.schedule, AppTheme.primary, 'Check-in opens', checkinOpens),
        const SizedBox(height: 12),
        if (canCollect) ...[
          _banner(Icons.payment, AppTheme.warning, 'Payment can be collected now', '₦${_fmtAmount(amountDue)}'),
          const SizedBox(height: 12),
          _paymentButtons(),
        ] else if (paymentStatus == 'paid') ...[
          _banner(Icons.check_circle, AppTheme.success, 'Paid', 'No action needed. Check-in opens later.'),
        ],
      ],
    );
  }

  // ── Scenario D: Already checked in ──

  Widget _buildAlreadyCheckedIn(List passengers) {
    return Column(
      children: [
        _banner(Icons.check_circle, AppTheme.success, 'All passengers checked in', null),
        const SizedBox(height: 8),
        ...passengers.where((p) => p['checked_in'] == true).map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 16, color: AppTheme.success),
              const SizedBox(width: 6),
              Text('${p['name']} (Seat ${p['seat_number'] ?? '?'})', style: const TextStyle(fontSize: 14)),
              if (p['checked_in_at'] != null) ...[
                const Spacer(),
                Text(_fmtTime(p['checked_in_at']), style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ],
          ),
        )),
      ],
    );
  }

  // ── Scenario E: Expired ──

  Widget _buildExpired() {
    return _banner(Icons.timer_off, AppTheme.error, 'Booking Expired', 'Payment deadline passed or booking was not confirmed.');
  }

  // ── Scenario F: Cancelled ──

  Widget _buildCancelled(Map<String, dynamic> booking) {
    return _banner(Icons.cancel, AppTheme.error, 'Booking Cancelled', booking['cancellation_reason']);
  }

  // ── Scenario G: Trip departed/completed ──

  Widget _buildTripGone(String reason, Map<String, dynamic> trip) {
    final isDeparted = reason == 'trip_departed';
    return _banner(
      isDeparted ? Icons.directions_bus : Icons.flag,
      Colors.grey[600]!,
      isDeparted ? 'Trip has already departed' : 'Trip has been completed',
      null,
    );
  }

  // ── Scenario H: Wrong terminal ──

  Widget _buildWrongTerminal(Map<String, dynamic> actions) {
    final termName = actions['wrong_terminal_name'] ?? 'another terminal';
    final agentTerm = actions['agent_terminal_name'] ?? 'your terminal';
    return _banner(
      Icons.wrong_location,
      AppTheme.warning,
      'Wrong Terminal',
      'This booking is for $termName. You can only process bookings for $agentTerm.',
    );
  }

  // ── Helpers ──

  Widget _banner(IconData icon, Color color, String title, String? subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
                if (subtitle != null && subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle, style: TextStyle(fontSize: 13, color: color.withValues(alpha: 0.8))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _closeButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onDismiss,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Close', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
      ),
    );
  }

  String _fmtAmount(dynamic amount) {
    if (amount == null) return '0';
    final num val = amount is num ? amount : double.tryParse(amount.toString()) ?? 0;
    return NumberFormat('#,##0', 'en_US').format(val);
  }

  String _fmtTime(String? dt) {
    if (dt == null || dt.isEmpty) return '';
    try {
      final d = DateTime.parse(dt);
      return DateFormat('hh:mm a').format(d);
    } catch (_) {
      return dt;
    }
  }
}
