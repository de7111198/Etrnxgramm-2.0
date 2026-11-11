import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!email.contains('@') || email.endsWith('@')) {
      setState(() => _error = 'Проверь адрес электронной почты.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
      );
      if (!mounted) return;
      setState(() => _codeSent = true);
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось отправить код. Попробуй позже.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Введи код из письма.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось проверить код. Попробуй ещё раз.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.forum_rounded,
                    size: 64,
                    color: Color(0xFFB99AFF),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Вход в Etrnxgram',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Введи почту — мы отправим одноразовый код для входа.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _emailController,
                    enabled: !_codeSent && !_loading,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Электронная почта',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeController,
                      enabled: !_loading,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Код из письма',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _loading
                        ? null
                        : (_codeSent ? _verifyCode : _sendCode),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_codeSent ? 'Подтвердить код' : 'Получить код'),
                  ),
                  if (_codeSent)
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                                _codeSent = false;
                                _codeController.clear();
                                _error = null;
                              }),
                      child: const Text('Изменить адрес почты'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BackendSetupPage extends StatelessWidget {
  const BackendSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 56, color: Color(0xFFB99AFF)),
                SizedBox(height: 18),
                Text(
                  'Сервер ещё не настроен',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 10),
                Text(
                  'Экран входа готов, но для подключения нужен проект Supabase. '
                  'Пока сервер не настроен, вход и синхронизация недоступны.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
