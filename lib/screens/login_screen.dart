import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:etbp_agent_mobile/config/theme.dart';
import 'package:etbp_agent_mobile/core/auth/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  Future<void> _checkExisting() async {
    final ok = await ref.read(authProvider.notifier).checkAuth();
    if (ok && mounted) context.go('/home');
  }

  Future<void> _login() async {
    if (_emailC.text.trim().isEmpty || _passC.text.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).login(_emailC.text.trim(), _passC.text);
      if (mounted) context.go('/home');
    } catch (e) { setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 60),
      const Icon(Icons.support_agent, size: 56, color: AppTheme.primary),
      const SizedBox(height: 16),
      const Text('Agent Mobile', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const Text('Enviable Transport', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
      const SizedBox(height: 40),
      if (_error != null) Container(padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13))),
      TextFormField(controller: _emailC, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
      const SizedBox(height: 16),
      TextFormField(controller: _passC, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
      const SizedBox(height: 24),
      ElevatedButton(onPressed: _loading ? null : _login, child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign In')),
    ]))),
  );
}
