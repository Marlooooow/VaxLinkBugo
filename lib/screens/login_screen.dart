import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../repositories/auth_repository.dart';
import '../repositories/demo_repository.dart';
import '../utils/user_facing_error.dart';
import '../services/session_context.dart';
import '../widgets/app_logo.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/app_loading.dart';
import 'app_shell.dart';
import 'change_password_screen.dart';

import 'guardian_activation_screen.dart';

class LoginScreen extends StatefulWidget {
  final AuthRepository authRepository;

  const LoginScreen({super.key, required this.authRepository});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await widget.authRepository.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (user == null || !user.active) {
        setState(() {
          _errorMessage = 'We could not verify those login details.';
        });
        return;
      }

    if (user.mustChangePassword) {
      SessionContext.setUser(user);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChangePasswordScreen(
            user: user,
            authRepository: widget.authRepository,
          ),
        ),
      );
    } else {
      _goToDashboard(user);
    }
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = UserFacingError.message(
          error,
          fallback: 'Sign-in could not be completed. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToDashboard(AppUser user) {
    SessionContext.setUser(user);
    final screen = AppShell(user: user, authRepository: widget.authRepository);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _fillDemo({required String username, required String password}) {
    _usernameController.text = username;
    _passwordController.text = password;
    setState(() => _errorMessage = null);
  }

  Future<void> _activateGuardianAccess() async {
    final credentials =
        await Navigator.push<({String username, String password})>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                GuardianActivationScreen(authRepository: widget.authRepository),
          ),
        );
    if (credentials == null || !mounted) return;
    _usernameController.text = credentials.username;
    _passwordController.text = credentials.password;
    setState(() => _errorMessage = null);
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _usernameController.text);
    final username = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forgot password?'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Guardian ID'),
          autocorrect: false,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Request reset')),
        ],
      ),
    );
    controller.dispose();
    if (username == null || username.trim().isEmpty || !mounted) return;
    try {
      final found = await widget.authRepository.requestGuardianPasswordReset(
        username,
      );
      if (!mounted) return;
      if (!found) {
        setState(() {
          _errorMessage =
              'Guardian ID not found. Check the ID and try again.';
        });
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Guardian ID verified. Your password-reset request was sent to the health worker.',
        ),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserFacingError.message(error, fallback: 'The reset request could not be sent.'))),
      );
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.loginTheme,
      child: Builder(builder: _buildLogin),
    );
  }

  Widget _buildLogin(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            AppLoadingOverlay(
              visible: _isLoading,
              title: 'Signing you in',
              message:
                  'Verifying your account and loading your secure workspace.',
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 470),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: AppLogo(size: 72)),

                        const SizedBox(height: 30),

                        const Text(
                          'Welcome back',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 7),

                        Text(
                          'Sign in to access your vaccination services securely.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            height: 1.4,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 28),

                        const _FieldLabel(
                          label: 'Username',
                          icon: Icons.person_outline_rounded,
                        ),

                        const SizedBox(height: 8),

                        TextField(
                          controller: _usernameController,
                          enabled: !_isLoading,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Enter your username',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),

                        const SizedBox(height: 18),

                        const _FieldLabel(
                          label: 'Password',
                          icon: Icons.lock_outline_rounded,
                        ),

                        const SizedBox(height: 8),

                        TextField(
                          controller: _passwordController,
                          enabled: !_isLoading,
                          obscureText: _obscurePassword,
                          onSubmitted: (_) {
                            if (!_isLoading) {
                              _login();
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Enter your password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 14),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 22),

                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            child: Text(_isLoading ? 'Signing in…' : 'Sign In'),
                          ),
                        ),

                        Center(
                          child: TextButton.icon(
                            onPressed: _isLoading ? null : _forgotPassword,
                            icon: const Icon(Icons.lock_reset_rounded, size: 18),
                            label: const Text('Forgot password?'),
                          ),
                        ),

                        Center(
                          child: TextButton(
                            onPressed: _isLoading
                                ? null
                                : _activateGuardianAccess,
                            child: const Text(
                              'Activate guardian online access',
                            ),
                          ),
                        ),
                        if (widget.authRepository is DemoRepository) ...[
                          const SizedBox(height: 12),

                          const _SectionDivider(label: 'Prototype Demo'),

                          const SizedBox(height: 16),

                          Text(
                            'Tap an account to fill in its prototype login details.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12.5,
                            ),
                          ),

                          const SizedBox(height: 11),

                          _DemoAccountButton(
                            icon: Icons.family_restroom_rounded,
                            name: 'Maria Santos',
                            role: 'Guardian',
                            username: 'guardian',
                            password: 'guardian123',
                            onTap: () {
                              if (!_isLoading) {
                                _fillDemo(
                                  username: 'guardian',
                                  password: 'guardian123',
                                );
                              }
                            },
                          ),

                          const SizedBox(height: 9),

                          _DemoAccountButton(
                            icon: Icons.family_restroom_rounded,
                            name: 'Paolo Mendoza',
                            role: 'Guardian',
                            username: 'paolo.guardian',
                            password: 'guardian123',
                            onTap: () {
                              if (!_isLoading) {
                                _fillDemo(
                                  username: 'paolo.guardian',
                                  password: 'guardian123',
                                );
                              }
                            },
                          ),

                          const SizedBox(height: 9),

                          _DemoAccountButton(
                            icon: Icons.family_restroom_rounded,
                            name: 'Grace Villanueva',
                            role: 'Guardian',
                            username: 'grace.guardian',
                            password: 'guardian123',
                            onTap: () {
                              if (!_isLoading) {
                                _fillDemo(
                                  username: 'grace.guardian',
                                  password: 'guardian123',
                                );
                              }
                            },
                          ),

                          const SizedBox(height: 9),

                          _DemoAccountButton(
                            icon: Icons.admin_panel_settings_outlined,
                            name: 'Barangay Health Administrator',
                            role: 'Administrator',
                            username: 'admin',
                            password: 'admin123',
                            onTap: () {
                              if (!_isLoading) {
                                _fillDemo(
                                  username: 'admin',
                                  password: 'admin123',
                                );
                              }
                            },
                          ),

                          const SizedBox(height: 9),

                          _DemoAccountButton(
                            icon: Icons.medical_services_outlined,
                            name: 'Nurse Maria Reyes',
                            role: 'Health Worker',
                            username: 'healthworker',
                            password: 'health123',
                            onTap: () {
                              if (!_isLoading) {
                                _fillDemo(
                                  username: 'healthworker',
                                  password: 'health123',
                                );
                              }
                            },
                          ),
                        ],
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 10),

                              Text(
                                widget.authRepository is DemoRepository
                                    ? 'Prototype authentication is simulated'
                                    : 'Sign in with your registered account',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Floating theme toggle — does not create a header
            Positioned(top: 4, right: 8, child: ThemeModeButton()),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final IconData icon;

  const _FieldLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SectionDivider extends StatelessWidget {
  final String label;

  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }
}

class _DemoAccountButton extends StatelessWidget {
  final IconData icon;
  final String name;
  final String role;
  final String username;
  final String password;
  final VoidCallback onTap;

  const _DemoAccountButton({
    required this.icon,
    required this.name,
    required this.role,
    required this.username,
    required this.password,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: primary.withValues(alpha: 0.045),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: primary.withValues(alpha: 0.16)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: primary.withValues(alpha: 0.10),
                child: Icon(icon, color: primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$role • $username / $password',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.login_rounded, color: primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
