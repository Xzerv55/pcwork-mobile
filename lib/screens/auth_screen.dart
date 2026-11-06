import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.baseUrl,
    required this.english,
    this.initialRegister = false,
  });

  final String baseUrl;
  final bool english;
  final bool initialRegister;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const Color cyan = Color(0xFF21D4D8);
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  late bool _register;
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;

  bool get _en => widget.english;
  String tr(String bg, String en) => _en ? en : bg;

  @override
  void initState() {
    super.initState();
    _register = widget.initialRegister;
  }

  @override
  void dispose() {
    _name.dispose();
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = AuthService(baseUrl: widget.baseUrl);
      final user = _register
          ? await service.register(
              _name.text,
              _identifier.text,
              _password.text,
            )
          : await service.login(_identifier.text, _password.text);
      if (mounted) Navigator.of(context).pop(user);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final base = widget.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$base/wp-login.php?action=lostpassword');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      setState(() => _error = tr(
            'Адресът за възстановяване на парола е невалиден.',
            'The password recovery address is invalid.',
          ));
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      setState(() => _error = tr(
            'Не успяхме да отворим страницата за възстановяване.',
            'Could not open the password recovery page.',
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('PCWork профил', 'PCWork account')),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF102234), Color(0xFF0A101A)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 94,
                              height: 94,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0B1724),
                                borderRadius: BorderRadius.circular(26),
                                border: Border.all(color: cyan.withValues(alpha: .35)),
                              ),
                              child: Image.asset('assets/images/LogoPCwork.png', fit: BoxFit.contain),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _register
                                ? tr('Създай PCWork профил', 'Create your PCWork account')
                                : tr('Добре дошъл обратно', 'Welcome back'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            _register
                                ? tr('Регистрация с имейл и парола.', 'Register with your email and password.')
                                : tr('Влез с данните на своя PCWork профил.', 'Sign in with your PCWork account details.'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                          const SizedBox(height: 22),
                          if (_register) ...[
                            TextFormField(
                              controller: _name,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: tr('Име и фамилия', 'Full name'),
                                prefixIcon: const Icon(Icons.person_outline),
                              ),
                              validator: (value) => (value ?? '').trim().length < 2
                                  ? tr('Въведи име.', 'Enter your name.')
                                  : null,
                            ),
                            const SizedBox(height: 13),
                          ],
                          TextFormField(
                            controller: _identifier,
                            keyboardType: _register ? TextInputType.emailAddress : TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            textCapitalization: TextCapitalization.none,
                            autofillHints: _register ? const [AutofillHints.email] : const [AutofillHints.username, AutofillHints.email],
                            decoration: InputDecoration(
                              labelText: _register
                                  ? 'Email'
                                  : tr('Имейл или потребителско име', 'Email or username'),
                              prefixIcon: const Icon(Icons.alternate_email),
                            ),
                            validator: (value) {
                              final text = (value ?? '').trim();
                              if (text.isEmpty) return tr('Полето е задължително.', 'This field is required.');
                              if (_register && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
                                return tr('Въведи валиден имейл.', 'Enter a valid email address.');
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 13),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscurePassword,
                            autofillHints: _register ? const [AutofillHints.newPassword] : const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) { if (!_busy) _submit(); },
                            decoration: InputDecoration(
                              labelText: tr('Парола', 'Password'),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword ? tr('Покажи паролата', 'Show password') : tr('Скрий паролата', 'Hide password'),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              ),
                            ),
                            validator: (value) {
                              final text = value ?? '';
                              if (text.isEmpty) return tr('Въведи парола.', 'Enter your password.');
                              if (_register && text.length < 10) return tr('Минимум 10 символа.', 'At least 10 characters.');
                              return null;
                            },
                          ),
                          if (!_register)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _busy ? null : _forgotPassword,
                                child: Text(tr('Забравена парола?', 'Forgot password?')),
                              ),
                            ),
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6B6B).withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: .35)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.error_outline, color: Color(0xFFFF8585), size: 20),
                                  const SizedBox(width: 9),
                                  Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFFFB0B0), fontSize: 12))),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 17),
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _submit,
                              icon: _busy
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Icon(_register ? Icons.person_add_alt_1 : Icons.login),
                              label: Text(_busy
                                  ? tr('Моля, изчакай…', 'Please wait…')
                                  : _register ? tr('Създай профил', 'Create account') : tr('Вход в приложението', 'Sign in to the app')),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _register = !_register;
                                      _error = null;
                                    }),
                            child: Text(_register
                                ? tr('Вече имаш профил? Влез', 'Already have an account? Sign in')
                                : tr('Нямаш профил? Регистрирай се', 'No account yet? Register')),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            tr('Входът използва твоя WordPress профил в pcwork-bg.com. Паролата не се записва в приложението.', 'Sign-in uses your WordPress account on pcwork-bg.com. Your password is not stored in the app.'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
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
      ),
    );
  }
}
