import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../root_shell.dart';
import 'login_screen.dart';

/// Entry-point widget shown at app startup. Blocks access to [RootShell]
/// (and therefore every screen of the app) until the user is logged in with
/// an approved account. Checks for a previously persisted session first so
/// returning users are not asked to log in on every launch.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  AppUser? _user;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final user = await AuthService.instance.currentUser;
    if (!mounted) return;
    setState(() {
      _user = (user != null && user.isApproved) ? user : null;
      _checking = false;
    });
  }

  void _onLoginSuccess() {
    _loadSession();
  }

  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: OkapiColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_user == null) {
      return LoginScreen(onLoginSuccess: _onLoginSuccess);
    }
    return RootShell(currentUser: _user!, onLogout: _logout);
  }
}
