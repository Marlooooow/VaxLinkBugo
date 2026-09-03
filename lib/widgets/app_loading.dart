import 'dart:async';

import 'package:flutter/material.dart';

/// The shared VaxLink waiting indicator. It remains meaningful without relying
/// on color and exposes a single live-region announcement to assistive tools.
class AppLoadingIndicator extends StatelessWidget {
  final double size;

  const AppLoadingIndicator({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              strokeWidth: size < 36 ? 2.4 : 3.2,
              color: colors.primary,
              backgroundColor: colors.primary.withValues(alpha: 0.12),
            ),
          ),
          Icon(
            Icons.vaccines_outlined,
            size: size * 0.43,
            color: colors.secondary,
          ),
        ],
      ),
    );
  }
}

class AppLoadingView extends StatelessWidget {
  final String title;
  final String message;
  final EdgeInsetsGeometry padding;

  const AppLoadingView({
    super.key,
    this.title = 'Loading information',
    this.message = 'Please wait a moment.',
    this.padding = const EdgeInsets.all(28),
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $message',
      child: Center(
        child: SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLoadingIndicator(size: 54),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

/// Blocks duplicate input while preserving the current screen as context.
class AppLoadingOverlay extends StatelessWidget {
  final bool visible;
  final String title;
  final String message;
  final Widget child;

  const AppLoadingOverlay({
    super.key,
    required this.visible,
    required this.child,
    this.title = 'Working securely',
    this.message = 'Please wait a moment.',
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        child,
        if (visible) ...[
          const Positioned.fill(
            child: ModalBarrier(dismissible: false, color: Color(0x66000000)),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  label: '$title. $message',
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 330),
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: colors.outlineVariant),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppLoadingIndicator(size: 50),
                          const SizedBox(height: 18),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              height: 1.4,
                              color: colors.onSurfaceVariant,
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
        ],
      ],
    );
  }
}

class _OperationOutcome {
  final Object? error;
  final StackTrace? stackTrace;
  const _OperationOutcome.success() : error = null, stackTrace = null;
  const _OperationOutcome.failure(this.error, this.stackTrace);
}

/// Runs an operation only after its blocking loading route is visible.
Future<void> runWithAppLoading(
  BuildContext context, {
  required String title,
  required String message,
  required Future<void> Function() operation,
}) async {
  final outcome = await showGeneralDialog<_OperationOutcome>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierLabel: 'Loading',
    barrierColor: Colors.black45,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => _OperationLoadingDialog(
      title: title,
      message: message,
      operation: operation,
    ),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
        child: child,
      ),
    ),
  );
  if (outcome?.error != null) {
    Error.throwWithStackTrace(outcome!.error!, outcome.stackTrace!);
  }
}

class _OperationLoadingDialog extends StatefulWidget {
  final String title;
  final String message;
  final Future<void> Function() operation;

  const _OperationLoadingDialog({
    required this.title,
    required this.message,
    required this.operation,
  });

  @override
  State<_OperationLoadingDialog> createState() =>
      _OperationLoadingDialogState();
}

class _OperationLoadingDialogState extends State<_OperationLoadingDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    _OperationOutcome outcome;
    try {
      await widget.operation();
      outcome = const _OperationOutcome.success();
    } catch (error, stackTrace) {
      outcome = _OperationOutcome.failure(error, stackTrace);
    }
    if (mounted) Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: AppLoadingOverlay(
            visible: true,
            title: widget.title,
            message: widget.message,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
