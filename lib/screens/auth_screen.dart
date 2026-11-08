import 'dart:async';

import 'package:flutter/material.dart';

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
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  late bool _register;
  bool _codeSent = false;
  bool _passwordMode = false;
  bool _acceptedTerms = false;
  bool _dataCollectionConsent = false;
  bool _busy = false;
  String? _error;
  String? _info;
  int _resendSeconds = 0;
  Timer? _timer;

  bool get _en => widget.english;
  String tr(String bg, String en) => _en ? en : bg;

  @override
  void initState() {
    super.initState();
    _register = widget.initialRegister;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _resendSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_register && !_codeSent && !_acceptedTerms) {
      setState(() => _error = tr('Необходимо е съгласие с общите условия и политиката за поверителност.', 'You must accept the Terms and Privacy Policy.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final service = AuthService(baseUrl: widget.baseUrl);
      if (!_register && _passwordMode) {
        final user = await service.loginWithPassword(
          identifier: _email.text.trim(),
          password: _password.text,
        );
        if (mounted) Navigator.of(context).pop(user);
      } else if (!_codeSent) {
        final message = await service.requestCode(
          register: _register,
          email: _email.text.trim(),
          name: _name.text,
          phone: _phone.text,
          dataCollectionOptIn: _register && _dataCollectionConsent,
        );
        if (!mounted) return;
        setState(() {
          _codeSent = true;
          _info = message;
        });
        _startCooldown();
      } else {
        final user = await service.verifyCode(
          register: _register,
          email: _email.text.trim(),
          code: _code.text.trim(),
        );
        if (mounted) Navigator.of(context).pop(user);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy || _resendSeconds > 0) return;
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      final message = await AuthService(baseUrl: widget.baseUrl).requestCode(
        register: _register,
        email: _email.text.trim(),
        name: _name.text,
        phone: _phone.text,
        dataCollectionOptIn: _register && _dataCollectionConsent,
      );
      if (mounted) {
        setState(() => _info = message);
        _startCooldown();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchMode() {
    _timer?.cancel();
    setState(() {
      _register = !_register;
      _codeSent = false;
      _passwordMode = false;
      _password.clear();
      _acceptedTerms = false;
      _dataCollectionConsent = false;
      _resendSeconds = 0;
      _code.clear();
      _error = null;
      _info = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('PCWork профил', 'PCWork account'))),
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
                              child: Image.asset('assets/images/LogoPCwork.webp', fit: BoxFit.contain),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _codeSent
                                ? tr('Потвърди имейла си', 'Verify your email')
                                : _register
                                    ? tr('Създай PCWork профил', 'Create your PCWork account')
                                    : tr('Добре дошъл обратно', 'Welcome back'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            _passwordMode
                                ? tr('Въведи WordPress паролата си. Входът без код е достъпен само ако администраторът го е разрешил за този профил.', 'Enter your WordPress password. Password sign-in is available only when an administrator has enabled it for this account.')
                                : _codeSent
                                    ? tr('Изпратихме шестцифрен код на ', 'We sent a six-digit code to ') + _email.text.trim()
                                    : _register
                                    ? tr('Регистрация с име, телефон и имейл. Кодът за потвърждение се изпраща само по имейл.', 'Register with your name, phone and email. Verification is by email only.')
                                    : tr('Въведи имейла си и ще ти изпратим еднократен код за вход.', 'Enter your email and we will send you a one-time sign-in code.'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                          const SizedBox(height: 22),
                          if (!_codeSent && _register) ...[
                            TextFormField(
                              controller: _name,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(labelText: tr('Име и фамилия', 'Full name'), prefixIcon: const Icon(Icons.person_outline)),
                              validator: (value) => (value ?? '').trim().length < 2 ? tr('Въведи име.', 'Enter your name.') : null,
                            ),
                            const SizedBox(height: 13),
                            TextFormField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(labelText: tr('Телефон', 'Phone'), prefixIcon: const Icon(Icons.phone_outlined)),
                              validator: (value) => (value ?? '').trim().replaceAll(RegExp(r'[^0-9+]'), '').length < 6 ? tr('Въведи валиден телефон.', 'Enter a valid phone number.') : null,
                            ),
                            const SizedBox(height: 13),
                          ],
                          if (!_codeSent)
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.done,
                              autocorrect: false,
                              enableSuggestions: false,
                              textCapitalization: TextCapitalization.none,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email)),
                              validator: (value) {
                                final text = (value ?? '').trim();
                                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) return tr('Въведи валиден имейл.', 'Enter a valid email address.');
                                return null;
                              },
                            ),
                          if (!_register && _passwordMode)
                            Padding(
                              padding: const EdgeInsets.only(top: 13),
                              child: TextFormField(
                                controller: _password,
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(labelText: tr('WordPress парола', 'WordPress password'), prefixIcon: const Icon(Icons.lock_outline)),
                                validator: (value) => (value ?? '').isEmpty ? tr('Въведи паролата си.', 'Enter your password.') : null,
                                onFieldSubmitted: (_) { if (!_busy) _submit(); },
                              ),
                            ),
                          if (_register && !_codeSent)
                            CheckboxListTile(
                              value: _acceptedTerms,
                              onChanged: _busy ? null : (value) => setState(() => _acceptedTerms = value == true),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(tr('Съгласен/на съм с общите условия и политиката за поверителност.', 'I agree to the Terms and Privacy Policy.'), style: const TextStyle(fontSize: 12)),
                            ),
                          if (_register && !_codeSent)
                            CheckboxListTile(
                              value: _dataCollectionConsent,
                              onChanged: _busy ? null : (value) => setState(() => _dataCollectionConsent = value == true),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                tr(
                                  'Съгласен/на съм PCWork да използва данните от профила ми за обслужване и да получавам маркетингови push известия. Съгласието е доброволно и може да бъде оттеглено.',
                                  'I agree that PCWork may use my profile data for customer service and send me marketing push notifications. This consent is optional and can be withdrawn.',
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          if (_codeSent && !_passwordMode)
                            TextFormField(
                              controller: _code,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              maxLength: 6,
                              autofocus: true,
                              decoration: InputDecoration(labelText: tr('Шестцифрен код', 'Six-digit code'), prefixIcon: const Icon(Icons.mark_email_read_outlined), counterText: ''),
                              validator: (value) => RegExp(r'^\d{6}$').hasMatch((value ?? '').trim()) ? null : tr('Въведи шестцифрения код.', 'Enter the six-digit code.'),
                              onFieldSubmitted: (_) { if (!_busy) _submit(); },
                            ),
                          if (_info != null) ...[
                            const SizedBox(height: 12),
                            Text(_info!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF7DE3C2), fontSize: 12)),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFFFF6B6B).withValues(alpha: .10), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: .35))),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.error_outline, color: Color(0xFFFF8585), size: 20), const SizedBox(width: 9), Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFFFB0B0), fontSize: 12)))]),
                            ),
                          ],
                          const SizedBox(height: 17),
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _submit,
                              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_codeSent ? Icons.verified_outlined : _register ? Icons.person_add_alt_1 : Icons.login),
                              label: Text(_busy ? tr('Моля, изчакай…', 'Please wait…') : _passwordMode ? tr('Вход с парола', 'Sign in with password') : _codeSent ? tr('Потвърди кода', 'Verify code') : _register ? tr('Изпрати код за регистрация', 'Send registration code') : tr('Изпрати код за вход', 'Send sign-in code')),
                            ),
                          ),
                          if (_codeSent && !_passwordMode) ...[
                            const SizedBox(height: 8),
                            TextButton(onPressed: _busy || _resendSeconds > 0 ? null : _resend, child: Text(_resendSeconds > 0 ? tr('Повторно изпращане след $_resendSeconds сек.', 'Resend in $_resendSeconds sec') : tr('Изпрати нов код', 'Send a new code'))),
                            TextButton(onPressed: _busy ? null : () { _timer?.cancel(); setState(() { _codeSent = false; _code.clear(); _resendSeconds = 0; _error = null; _info = null; }); }, child: Text(tr('Промени имейла', 'Change email'))),
                          ] else ...[
                            const SizedBox(height: 10),
                            if (!_register)
                              TextButton(
                                onPressed: _busy ? null : () => setState(() { _passwordMode = !_passwordMode; _password.clear(); _error = null; _info = null; }),
                                child: Text(_passwordMode ? tr('Вход с имейл код', 'Sign in with email code') : tr('Вход с парола (само за разрешени профили)', 'Sign in with password (authorized accounts only)')),
                              ),
                            TextButton(onPressed: _busy ? null : _switchMode, child: Text(_register ? tr('Вече имаш профил? Вход', 'Already registered? Sign in') : tr('Нямаш профил? Регистрация', 'No account? Register'))),
                          ],
                          const SizedBox(height: 5),
                          Text(tr('Кодът е валиден 5 минути. Не споделяй кода с никого. Не изпращаме SMS или Viber кодове.', 'The code is valid for 5 minutes. Never share it. We do not send SMS or Viber codes.'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
