import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/common_fields.dart';

/// Self-registration screen. New accounts are created with a "pending"
/// approval status and cannot log in until an administrator approves them
/// from the OKAPI Web Admin dashboard.
class RegisterScreen extends StatefulWidget {
  final VoidCallback onRegistered;
  const RegisterScreen({super.key, required this.onRegistered});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomPrenomCtrl = TextEditingController();
  final _telephoneCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  String _sexe = 'Masculin';
  String _statut = 'Enquêteur';
  String? _tablette;
  bool _obscurePassword = true;
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nomPrenomCtrl.dispose();
    _telephoneCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      setState(() => _errorMessage = 'Les mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    final result = await AuthService.instance.register(
      nomPrenom: _nomPrenomCtrl.text.trim(),
      telephone: _telephoneCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text,
      sexe: _sexe,
      statut: _statut,
      tablette: _tablette ?? '',
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.success) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Inscription envoyée'),
          content: Text(
            result.message.isNotEmpty
                ? result.message
                : 'Votre compte a été créé et est en attente de validation par un administrateur. Vous pourrez vous connecter dès que votre compte sera approuvé.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      widget.onRegistered();
    } else {
      setState(() => _errorMessage = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OkapiColors.background,
      appBar: AppBar(
        title: const Text('Créer un compte'),
        backgroundColor: OkapiColors.secondary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Inscription',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: OkapiColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Votre compte devra être approuvé par un administrateur avant de pouvoir vous connecter.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: OkapiColors.textLight,
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: OkapiColors.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: OkapiColors.error.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: OkapiColors.error,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _nomPrenomCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nom et prénom',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          textCapitalization: TextCapitalization.words,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Champ requis'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _telephoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Numéro de téléphone',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          keyboardType: TextInputType.phone,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Champ requis'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _usernameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nom d\'utilisateur',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Champ requis'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _sexe,
                          decoration: const InputDecoration(
                            labelText: 'Sexe',
                            prefixIcon: Icon(Icons.wc_outlined),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Masculin',
                              child: Text('Masculin'),
                            ),
                            DropdownMenuItem(
                              value: 'Féminin',
                              child: Text('Féminin'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _sexe = v ?? _sexe),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _statut,
                          decoration: const InputDecoration(
                            labelText: 'Statut',
                            prefixIcon: Icon(Icons.work_outline),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Chef d\'équipe',
                              child: Text('Chef d\'équipe'),
                            ),
                            DropdownMenuItem(
                              value: 'Enquêteur',
                              child: Text('Enquêteur'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _statut = v ?? _statut),
                        ),
                        const SizedBox(height: 14),
                        ChoiceDropdown(
                          listName: 'tablette',
                          label: 'Tablette assignée',
                          value: _tablette,
                          required: true,
                          onChanged: (v) => setState(() => _tablette = v),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Sélectionnez la tablette utilisée'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: (v) => (v == null || v.length < 4)
                              ? 'Au moins 4 caractères'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirmPasswordCtrl,
                          obscureText: _obscurePassword,
                          decoration: const InputDecoration(
                            labelText: 'Confirmer le mot de passe',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Champ requis' : null,
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: OkapiColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('S\'inscrire'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
