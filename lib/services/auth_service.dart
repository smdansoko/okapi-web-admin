import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'sync_service.dart';

/// A logged-in (or previously registered) OKAPI Survey user account, as
/// returned by the OKAPI Web Admin server (never includes the password).
class AppUser {
  final String id;
  final String nomPrenom;
  final String telephone;
  final String username;
  final String sexe;
  final String statut;
  final String approvalStatus; // pending / approved / rejected

  AppUser({
    required this.id,
    required this.nomPrenom,
    required this.telephone,
    required this.username,
    required this.sexe,
    required this.statut,
    required this.approvalStatus,
  });

  bool get isApproved => approvalStatus == 'approved';
  bool get isPending => approvalStatus == 'pending';
  bool get isRejected => approvalStatus == 'rejected';

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String? ?? '',
    nomPrenom: json['nomPrenom'] as String? ?? '',
    telephone: json['telephone'] as String? ?? '',
    username: json['username'] as String? ?? '',
    sexe: json['sexe'] as String? ?? '',
    statut: json['statut'] as String? ?? '',
    approvalStatus: json['approvalStatus'] as String? ?? 'pending',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nomPrenom': nomPrenom,
    'telephone': telephone,
    'username': username,
    'sexe': sexe,
    'statut': statut,
    'approvalStatus': approvalStatus,
  };
}

/// Simple result wrapper for auth operations.
class AuthResult {
  final bool success;
  final String message;
  final AppUser? user;

  AuthResult({required this.success, required this.message, this.user});
}

/// Handles user registration, login and approval-status checks against the
/// OKAPI Web Admin server, and persists the logged-in session locally so the
/// user does not need to log in again on every app launch.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _prefKeyLoggedInUser = 'auth_logged_in_user';

  AppUser? _cachedUser;

  /// Currently logged-in user (approved), if any, loaded from local cache.
  Future<AppUser?> get currentUser async {
    if (_cachedUser != null) return _cachedUser;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKeyLoggedInUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      _cachedUser = AppUser.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      _cachedUser = null;
    }
    return _cachedUser;
  }

  Future<void> _persistUser(AppUser user) async {
    _cachedUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyLoggedInUser, jsonEncode(user.toJson()));
  }

  Future<void> logout() async {
    _cachedUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyLoggedInUser);
  }

  Future<AuthResult> register({
    required String nomPrenom,
    required String telephone,
    required String username,
    required String password,
    required String sexe,
    required String statut,
  }) async {
    final url = await SyncService.instance.serverUrl;
    if (url.isEmpty) {
      return AuthResult(
        success: false,
        message:
            'Aucune adresse de serveur configurée. Veuillez configurer l\'adresse du serveur Web Admin OKAPI (onglet Synchroniser).',
      );
    }
    try {
      final response = await http
          .post(
            Uri.parse('$url/api/register'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'nomPrenom': nomPrenom,
              'telephone': telephone,
              'username': username,
              'password': password,
              'sexe': sexe,
              'statut': statut,
            }),
          )
          .timeout(const Duration(seconds: 20));

      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final status = body['status'] as String? ?? 'error';
      final message = body['message'] as String? ?? '';
      if (status == 'ok') {
        final userJson = body['user'] as Map<String, dynamic>?;
        return AuthResult(
          success: true,
          message: message.isNotEmpty
              ? message
              : 'Compte créé. En attente de validation par un administrateur.',
          user: userJson != null ? AppUser.fromJson(userJson) : null,
        );
      }
      return AuthResult(
        success: false,
        message: message.isNotEmpty
            ? message
            : 'Impossible de créer le compte.',
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message:
            'Connexion impossible au serveur. Vérifiez votre connexion et l\'adresse configurée.\n\nDétail : $e',
      );
    }
  }

  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    final url = await SyncService.instance.serverUrl;
    if (url.isEmpty) {
      return AuthResult(
        success: false,
        message:
            'Aucune adresse de serveur configurée. Veuillez configurer l\'adresse du serveur Web Admin OKAPI (onglet Synchroniser).',
      );
    }
    try {
      final response = await http
          .post(
            Uri.parse('$url/api/login'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 20));

      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final status = body['status'] as String? ?? 'error';
      final message = body['message'] as String? ?? '';
      final userJson = body['user'] as Map<String, dynamic>?;
      final user = userJson != null ? AppUser.fromJson(userJson) : null;

      if (status == 'ok' && user != null && user.isApproved) {
        await _persistUser(user);
        return AuthResult(
          success: true,
          message: message.isNotEmpty ? message : 'Connexion réussie.',
          user: user,
        );
      }
      if (status == 'pending') {
        return AuthResult(
          success: false,
          message: message.isNotEmpty
              ? message
              : 'Votre compte est en attente de validation par un administrateur.',
          user: user,
        );
      }
      if (status == 'rejected') {
        return AuthResult(
          success: false,
          message: message.isNotEmpty
              ? message
              : 'Votre demande d\'inscription a été refusée. Contactez un administrateur.',
          user: user,
        );
      }
      return AuthResult(
        success: false,
        message: message.isNotEmpty
            ? message
            : 'Identifiant ou mot de passe incorrect.',
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message:
            'Connexion impossible au serveur. Vérifiez votre connexion et l\'adresse configurée.\n\nDétail : $e',
      );
    }
  }

  /// Re-checks the approval status of a pending/rejected account (e.g. from
  /// a "Vérifier mon statut" button shown after registration).
  Future<AuthResult> checkStatus(String userId) async {
    final url = await SyncService.instance.serverUrl;
    try {
      final response = await http
          .get(Uri.parse('$url/api/users/$userId/status'))
          .timeout(const Duration(seconds: 15));
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final status = body['status'] as String? ?? 'error';
      final userJson = body['user'] as Map<String, dynamic>?;
      final user = userJson != null ? AppUser.fromJson(userJson) : null;
      if (status == 'ok' && user != null) {
        if (user.isApproved) await _persistUser(user);
        return AuthResult(success: true, message: '', user: user);
      }
      return AuthResult(
        success: false,
        message: body['message'] as String? ?? 'Compte introuvable.',
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Impossible de vérifier le statut du compte.\n\nDétail : $e',
      );
    }
  }
}
