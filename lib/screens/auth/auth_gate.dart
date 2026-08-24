import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../root_shell.dart';
import 'login_screen.dart';
import 'project_select_screen.dart';
import 'module_select_screen.dart';

/// Entry-point widget shown at app startup. Blocks access to [RootShell]
/// (and therefore every screen of the app) until the user is logged in with
/// an approved account, AND has chosen a PROJECT (SIMANDOU/WCAG/SMB) and a
/// MODULE (PARC/BIODIVERSITÉ/SOCIAL) for the current session — mirroring
/// the OKAPI Web Admin's own login -> select-project -> select-module flow.
/// Checks for a previously persisted session first so returning users are
/// not asked to log in / re-select on every launch.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _Step { checking, login, selectProject, selectModule, ready }

class _AuthGateState extends State<AuthGate> {
  _Step _step = _Step.checking;
  AppUser? _user;
  String? _project;
  String? _module;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final user = await AuthService.instance.currentUser;
    final approvedUser = (user != null && user.isApproved) ? user : null;

    if (approvedUser == null) {
      if (!mounted) return;
      setState(() {
        _user = null;
        _project = null;
        _module = null;
        _step = _Step.login;
      });
      return;
    }

    final project = await SessionService.instance.project;
    var module = await SessionService.instance.module;

    // Guard against a persisted module that is no longer allowed for this
    // account's statut (e.g. an admin changed the statut server-side).
    if (module != null &&
        !SessionService.allowedModulesForStatut(
          approvedUser.statut,
        ).contains(module)) {
      module = null;
      await SessionService.instance.clearModule();
    }

    if (!mounted) return;
    setState(() {
      _user = approvedUser;
      _project = project;
      _module = module;
      if (project == null) {
        _step = _Step.selectProject;
      } else if (module == null) {
        _step = _Step.selectModule;
      } else {
        _step = _Step.ready;
      }
    });
  }

  void _onLoginSuccess() {
    _loadSession();
  }

  void _onProjectSelected(String code) {
    setState(() {
      _project = code;
      _step = _Step.selectModule;
    });
  }

  void _onModuleSelected(String code) {
    setState(() {
      _module = code;
      _step = _Step.ready;
    });
  }

  void _onChangeProject() {
    SessionService.instance.clearAll();
    setState(() {
      _project = null;
      _module = null;
      _step = _Step.selectProject;
    });
  }

  void _onChangeModule() {
    SessionService.instance.clearModule();
    setState(() {
      _module = null;
      _step = _Step.selectModule;
    });
  }

  Future<void> _logout() async {
    await AuthService.instance.logout();
    await SessionService.instance.clearAll();
    if (!mounted) return;
    setState(() {
      _user = null;
      _project = null;
      _module = null;
      _step = _Step.login;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.checking:
        return const Scaffold(
          backgroundColor: OkapiColors.background,
          body: Center(child: CircularProgressIndicator()),
        );
      case _Step.login:
        return LoginScreen(onLoginSuccess: _onLoginSuccess);
      case _Step.selectProject:
        return ProjectSelectScreen(
          currentUser: _user!,
          onProjectSelected: _onProjectSelected,
          onLogout: _logout,
        );
      case _Step.selectModule:
        return ModuleSelectScreen(
          currentUser: _user!,
          projectCode: _project!,
          onModuleSelected: _onModuleSelected,
          onChangeProject: _onChangeProject,
          onLogout: _logout,
        );
      case _Step.ready:
        return RootShell(
          currentUser: _user!,
          projectCode: _project!,
          moduleCode: _module!,
          onLogout: _logout,
          onChangeModule: _onChangeModule,
          onChangeProject: _onChangeProject,
        );
    }
  }
}
