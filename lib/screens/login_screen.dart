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
import 'staff_activation_screen.dart';

class LoginScreen extends StatefulWidget {
  final AuthRepository authRepository;

  const LoginScreen({
    super.key,
    required this.authRepository,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  // ================================================================
  // LOGIN
  // ================================================================

  Future<void> _login() async {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // Basic client-side validation.
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage =
            'Please enter your username and password.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await widget.authRepository.login(
        username: username,
        password: password,
      );

      if (!mounted) return;

      if (user == null || !user.active) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'We could not verify those login details. '
              'Please check your username and password.';
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

      setState(() {
        _errorMessage = UserFacingError.message(
          error,
          fallback:
              'Sign-in could not be completed. Please try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ================================================================
  // DASHBOARD
  // ================================================================

  void _goToDashboard(AppUser user) {
    SessionContext.setUser(user);

    final screen = AppShell(
      user: user,
      authRepository: widget.authRepository,
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  // ================================================================
  // DEMO LOGIN
  // ================================================================

  void _fillDemo({
    required String username,
    required String password,
  }) {
    _usernameController.text = username;
    _passwordController.text = password;

    setState(() {
      _errorMessage = null;
    });

    _passwordFocusNode.requestFocus();
  }

  // ================================================================
  // GUARDIAN ACTIVATION
  // ================================================================

  Future<void> _activateGuardianAccess() async {
    final credentials =
        await Navigator.push<({String username, String password})>(
      context,
      MaterialPageRoute(
        builder: (_) => GuardianActivationScreen(
          authRepository: widget.authRepository,
        ),
      ),
    );

    if (credentials == null || !mounted) return;

    _usernameController.text = credentials.username;
    _passwordController.text = credentials.password;

    setState(() {
      _errorMessage = null;
    });
  }

  // ================================================================
  // STAFF ACTIVATION
  // ================================================================

  Future<void> _activateStaffAccess() async {
    final credentials =
        await Navigator.push<({String username, String password})>(
      context,
      MaterialPageRoute(
        builder: (_) => StaffActivationScreen(
          authRepository: widget.authRepository,
        ),
      ),
    );

    if (credentials == null || !mounted) return;

    _usernameController.text = credentials.username;
    _passwordController.text = credentials.password;

    setState(() {
      _errorMessage = null;
    });
  }

  // ================================================================
  // ACCESS OPTIONS BOTTOM SHEET
  // ================================================================

  Future<void> _showAccessOptions() async {
    if (_isLoading) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) {
        final colors =
            Theme.of(sheetContext).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              4,
              20,
              20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                // ------------------------------------------------------
                // TITLE
                // ------------------------------------------------------

                Text(
                  'Get online access',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'Choose the type of account you want to activate.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: colors.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 20),

                // ------------------------------------------------------
                // GUARDIAN
                // ------------------------------------------------------

                _AccessOption(
                  icon: Icons.family_restroom_rounded,
                  title: 'Guardian access',
                  description:
                      'For parents and guardians managing a child\'s '
                      'immunization records.',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _activateGuardianAccess();
                  },
                ),

                // ------------------------------------------------------
                // STAFF
                // ------------------------------------------------------

                if (widget.authRepository
                    is! DemoRepository) ...[
                  const SizedBox(height: 10),

                  _AccessOption(
                    icon: Icons.medical_services_outlined,
                    title: 'Staff access',
                    description:
                        'For authorized barangay health personnel.',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _activateStaffAccess();
                    },
                  ),
                ],

                const SizedBox(height: 12),

                // ------------------------------------------------------
                // CANCEL
                // ------------------------------------------------------

                TextButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                  },
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ================================================================
  // FORGOT PASSWORD
  // ================================================================

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(
      text: _usernameController.text,
    );

    final username = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset your password'),
          content: TextField(
            controller: controller,
            autofocus: true,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Guardian ID',
              hintText: 'Enter your Guardian ID',
              prefixIcon: Icon(
                Icons.badge_outlined,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  controller.text.trim(),
                );
              },
              child: const Text('Request reset'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (username == null ||
        username.trim().isEmpty ||
        !mounted) {
      return;
    }

    try {
      final found = await widget.authRepository
          .requestGuardianPasswordReset(username);

      if (!mounted) return;

      if (!found) {
        setState(() {
          _errorMessage =
              'Guardian ID not found. Check the ID and try again.';
        });
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Guardian ID verified. Your password-reset request '
            'was sent to the health worker.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            UserFacingError.message(
              error,
              fallback:
                  'The reset request could not be sent.',
            ),
          ),
        ),
      );
    }
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.loginTheme,
      child: Builder(
        builder: _buildLogin,
      ),
    );
  }

  Widget _buildLogin(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    24,
                    28,
                    24,
                    40,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 430,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        // ==================================================
                        // BRAND
                        // ==================================================

                        const Center(
                          child: AppLogo(size: 72),
                        ),

                        const SizedBox(height: 32),

                        // ==================================================
                        // WELCOME
                        // ==================================================

                        Text(
                          'Welcome back!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                            color: colors.onSurface,
                          ),
                        ),


                        const SizedBox(height: 15),

                        // ==================================================
                        // USERNAME
                        // ==================================================

                        const _FieldLabel(
                          label: 'Username',
                          icon:
                              Icons.person_outline_rounded,
                        ),

                        const SizedBox(height: 8),

                        TextField(
                          controller: _usernameController,
                          focusNode: _usernameFocusNode,
                          enabled: !_isLoading,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction:
                              TextInputAction.next,
                          onSubmitted: (_) {
                            _passwordFocusNode.requestFocus();
                          },
                          decoration:
                              const InputDecoration(
                            hintText:
                                'Enter your username',
                            prefixIcon: Icon(
                              Icons
                                  .person_outline_rounded,
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // ==================================================
                        // PASSWORD
                        // ==================================================

                        const _FieldLabel(
                          label: 'Password',
                          icon:
                              Icons.lock_outline_rounded,
                        ),

                        const SizedBox(height: 8),

                        TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          enabled: !_isLoading,
                          obscureText: _obscurePassword,
                          textInputAction:
                              TextInputAction.done,
                          onSubmitted: (_) {
                            if (!_isLoading) {
                              _login();
                            }
                          },
                          decoration: InputDecoration(
                            hintText:
                                'Enter your password',
                            prefixIcon: const Icon(
                              Icons
                                  .lock_outline_rounded,
                            ),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      setState(() {
                                        _obscurePassword =
                                            !_obscurePassword;
                                      });
                                    },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons
                                        .visibility_outlined
                                    : Icons
                                        .visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),

                        // ==================================================
                        // FORGOT PASSWORD
                        // ==================================================

                        Align(
                          alignment:
                              Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading
                                ? null
                                : _forgotPassword,
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets
                                      .symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              minimumSize:
                                  const Size(48, 40),
                            ),
                            child: const Text(
                              'Forgot password?',
                            ),
                          ),
                        ),

                        // ==================================================
                        // ERROR
                        // ==================================================

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 2),
                          _LoginError(
                            message: _errorMessage!,
                          ),
                        ],

                        const SizedBox(height: 14),

                        // ==================================================
                        // SIGN IN BUTTON
                        // ==================================================

                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            onPressed:
                                _isLoading ? null : _login,
                            child: Text(
                              _isLoading
                                  ? 'Signing in…'
                                  : 'Sign in',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ==================================================
                        // ACCESS
                        // ==================================================

                        Text(
                          'Need online access?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),

                        const SizedBox(height: 2),

                        Center(
                          child: TextButton.icon(
                            onPressed: _isLoading
                                ? null
                                : _showAccessOptions,
                            icon: const Icon(
                              Icons
                                  .person_add_alt_1_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'Activate account',
                            ),
                          ),
                        ),

                        // ==================================================
                        // DEMO SECTION
                        // ==================================================

                        if (widget.authRepository
                            is DemoRepository) ...[
                          const SizedBox(height: 20),

                          const _SectionDivider(
                            label: 'Prototype Demo',
                          ),

                          const SizedBox(height: 14),

                          Text(
                            'Tap an account to automatically fill in the login details.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color:
                                  colors.onSurfaceVariant,
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),

                          const SizedBox(height: 13),

                          _DemoAccountButton(
                            icon: Icons
                                .family_restroom_rounded,
                            name: 'Maria Santos',
                            role: 'Guardian',
                            username: 'guardian',
                            password: 'guardian123',
                            onTap: () {
                              if (!_isLoading) {
                                _fillDemo(
                                  username: 'guardian',
                                  password:
                                      'guardian123',
                                );
                              }
                            },
                          ),

                          const SizedBox(height: 9),

                          _DemoAccountButton(
                            icon: Icons
                                .family_restroom_rounded,
                            name: 'Paolo Mendoza',
                            role: 'Guardian',
                            username:
                                'paolo.guardian',
                            password: 'guardian123',
                            onTap: () {
                              if (!_isLoading) {
                                _fillDemo(
                                  username:
                                      'paolo.guardian',
                                  password:
                                      'guardian123',
                                );
                              }
                            },
                          ),

                          const SizedBox(height: 9),

                          _DemoAccountButton(
                            icon: Icons
                                .family_restroom_rounded,
                            name: 'Grace Villanueva',
                            role: 'Guardian',
                            username:
                                'grace.guardian',
                            password: 'guardian123',
                            onTap: () {
                              if (!_isLoading) {
                                _fillDemo(
                                  username:
                                      'grace.guardian',
                                  password:
                                      'guardian123',
                                );
                              }
                            },
                          ),

                          const SizedBox(height: 9),

                          _DemoAccountButton(
                            icon: Icons
                                .admin_panel_settings_outlined,
                            name:
                                'Barangay Health Administrator',
                            role: 'Administrator',
                            username: 'admin',
                            password: 'admin123',
                            onTap: () {
                              if (!_isLoading) {
                                _fillDemo(
                                  username: 'admin',
                                  password:
                                      'admin123',
                                );
                              }
                            },
                          ),

                          const SizedBox(height: 9),

                          _DemoAccountButton(
                            icon: Icons
                                .medical_services_outlined,
                            name: 'Nurse Maria Reyes',
                            role: 'Health Worker',
                            username:
                                'healthworker',
                            password: 'health123',
                            onTap: () {
                              if (!_isLoading) {
                                _fillDemo(
                                  username:
                                      'healthworker',
                                  password:
                                      'health123',
                                );
                              }
                            },
                          ),
                        ],

                        // ==================================================
                        // SECURITY MESSAGE
                        // ==================================================

                        const SizedBox(height: 26),

                        _SecurityMessage(
                          text: widget.authRepository
                                  is DemoRepository
                              ? 'Prototype authentication is simulated'
                              : 'Your account is protected and accessible only to authorized users.',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ============================================================
            // THEME TOGGLE
            // ============================================================

            Positioned(
              top: 4,
              right: 8,
              child: ThemeModeButton(),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// FIELD LABEL
// ======================================================================

class _FieldLabel extends StatelessWidget {
  final String label;
  final IconData icon;

  const _FieldLabel({
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }
}

// ======================================================================
// ACCESS OPTION
// ======================================================================

class _AccessOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _AccessOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surfaceContainerHighest.withValues(
        alpha: 0.45,
      ),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment:
                CrossAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius:
                      BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: colors.primary,
                  size: 23,
                ),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color:
                            colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// LOGIN ERROR
// ======================================================================

class _LoginError extends StatelessWidget {
  final String message;

  const _LoginError({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colors.error.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: colors.error,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colors.error,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// SECTION DIVIDER
// ======================================================================

class _SectionDivider extends StatelessWidget {
  final String label;

  const _SectionDivider({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Divider(
            color: colors.outlineVariant,
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: colors.outlineVariant,
          ),
        ),
      ],
    );
  }
}

// ======================================================================
// SECURITY MESSAGE
// ======================================================================

class _SecurityMessage extends StatelessWidget {
  final String text;

  const _SecurityMessage({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.3,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

// ======================================================================
// DEMO ACCOUNT BUTTON
// ======================================================================

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
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;

    return Material(
      color: primary.withValues(alpha: 0.045),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: primary.withValues(alpha: 0.16),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    primary.withValues(alpha: 0.10),
                child: Icon(
                  icon,
                  color: primary,
                  size: 20,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$role • $username / $password',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            colors.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Icon(
                Icons.login_rounded,
                color: primary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
