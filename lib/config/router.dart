import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:etbp_agent_mobile/screens/login_screen.dart';
import 'package:etbp_agent_mobile/screens/home_screen.dart';
import 'package:etbp_agent_mobile/screens/qr_scanner_screen.dart';
import 'package:etbp_agent_mobile/screens/wallet_payment_screen.dart';
import 'package:etbp_agent_mobile/screens/token_screen.dart';

final routerProvider = Provider<GoRouter>((ref) => GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/scanner', builder: (_, __) => const QRScannerScreen()),
    GoRoute(path: '/wallet-payment', builder: (_, __) => const WalletPaymentScreen()),
    GoRoute(path: '/token', builder: (_, __) => const TokenScreen()),
  ],
));
