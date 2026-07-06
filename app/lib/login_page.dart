import 'package:flutter/material.dart';

import 'auth.dart';
import 'home_page.dart';
import 'task_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _registerMode = true;
  bool _busy = false;
  String? _error;
  bool _showAdvanced = false;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _serverUrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      _serverUrl.text = p.getString(PrefKeys.serverUrl) ?? defaultServerUrl;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _serverUrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _busy = true;
    });

    // Persist the (possibly customised) server URL before auth call.
    final p = await SharedPreferences.getInstance();
    final url = _serverUrl.text.trim().isEmpty ? defaultServerUrl : _serverUrl.text.trim();
    await p.setString(PrefKeys.serverUrl, url);

    final email = _email.text.trim();
    final pw = _password.text;
    if (email.isEmpty || pw.length < 4 || (_registerMode && _name.text.trim().isEmpty)) {
      setState(() {
        _busy = false;
        _error = 'Fill in all fields (password at least 4 characters).';
      });
      return;
    }

    final res = _registerMode
        ? await Auth.register(_name.text.trim(), email, pw)
        : await Auth.login(email, pw);

    if (!mounted) return;
    if (res.ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } else {
      setState(() {
        _busy = false;
        _error = res.error;
      });
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.location_on, size: 56, color: Color(0xFF4D8DFF)),
                  const SizedBox(height: 8),
                  Text('Field Tracker',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(_registerMode ? 'Create your account' : 'Sign in',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).hintColor)),
                  const SizedBox(height: 24),

                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),

                  if (_registerMode) ...[
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Your name', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                        labelText: 'Email', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Password', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),

                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_registerMode ? 'Create account' : 'Sign in'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _registerMode = !_registerMode;
                              _error = null;
                            }),
                    child: Text(_registerMode
                        ? 'I already have an account - Sign in'
                        : 'New here? Create an account'),
                  ),

                  const Divider(height: 28),
                  if (!_showAdvanced)
                    TextButton(
                      onPressed: () => setState(() => _showAdvanced = true),
                      child: const Text('Advanced: change server URL'),
                    )
                  else
                    TextField(
                      controller: _serverUrl,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Server URL',
                        border: OutlineInputBorder(),
                        helperText: 'Only change this if your manager tells you to',
                      ),
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
