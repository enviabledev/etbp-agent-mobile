import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etbp_agent_mobile/config/theme.dart';
import 'package:etbp_agent_mobile/core/auth/auth_provider.dart';
import 'package:etbp_agent_mobile/core/api/endpoints.dart';

class TokenScreen extends ConsumerStatefulWidget {
  const TokenScreen({super.key});
  @override
  ConsumerState<TokenScreen> createState() => _TokenScreenState();
}

class _TokenScreenState extends ConsumerState<TokenScreen> {
  String? _code;
  int _secondsLeft = 0;
  Timer? _timer;
  bool _generating = false;

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post(Endpoints.generateToken);
      _timer?.cancel();
      setState(() { _code = res.data['code']; _secondsLeft = res.data['expires_in'] ?? 600; _generating = false; });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_secondsLeft <= 0) { _timer?.cancel(); setState(() { _code = null; }); return; }
        setState(() => _secondsLeft--);
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _generating = false);
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Auth Token')),
    body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.key, size: 48, color: Color(0xFF7C3AED)),
      const SizedBox(height: 24),
      if (_code != null) ...[
        Text(_code!.split('').join('  '), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, letterSpacing: 8, fontFamily: 'monospace')),
        const SizedBox(height: 16),
        Text('${(_secondsLeft ~/ 60).toString().padLeft(2, '0')}:${(_secondsLeft % 60).toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 20, color: AppTheme.textSecondary)),
        const SizedBox(height: 16),
        TextButton.icon(icon: const Icon(Icons.copy, size: 16), label: const Text('Copy'), onPressed: () { Clipboard.setData(ClipboardData(text: _code!)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied'))); }),
        const SizedBox(height: 32),
        const Text('Use this code to verify customer identity\nor login to the agent portal', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      ] else ...[
        const Text('Generate a 6-digit verification code', style: TextStyle(color: AppTheme.textSecondary)),
      ],
      const SizedBox(height: 24),
      ElevatedButton(onPressed: _generating ? null : _generate,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
        child: _generating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_code != null ? 'Generate New' : 'Generate Token')),
      const SizedBox(height: 12),
      const Text('All generated tokens are logged for security', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
    ]))),
  );
}
