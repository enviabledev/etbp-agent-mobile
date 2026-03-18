import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:etbp_agent_mobile/config/theme.dart';
import 'package:etbp_agent_mobile/core/auth/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(auth.agentName ?? 'Agent', style: const TextStyle(fontSize: 16)),
          if (auth.terminalName != null) Text(auth.terminalName!, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.normal)),
        ]),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () async { await ref.read(authProvider.notifier).logout(); if (context.mounted) context.go('/login'); })],
      ),
      body: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        const SizedBox(height: 20),
        _card(context, 'QR Check-in Scanner', 'Scan passenger boarding passes', Icons.qr_code_scanner, AppTheme.primary, () => context.push('/scanner')),
        const SizedBox(height: 16),
        _card(context, 'Wallet Payment', 'Process wallet payments at counter', Icons.account_balance_wallet, AppTheme.success, () => context.push('/wallet-payment')),
        const SizedBox(height: 16),
        _card(context, 'Generate Auth Token', 'Generate 6-digit verification code', Icons.key, const Color(0xFF7C3AED), () => context.push('/token')),
      ])),
    );
  }

  Widget _card(BuildContext context, String title, String subtitle, IconData icon, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Icon(icon, size: 40, color: Colors.white),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
        ])),
        const Icon(Icons.chevron_right, color: Colors.white),
      ]),
    ),
  );
}
