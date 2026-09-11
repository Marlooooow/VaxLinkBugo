import 'dart:async';

import 'package:flutter/material.dart';

enum AppFeedbackType { success, failure }

/// Displays lightweight, non-blocking operation feedback above the current UI.
/// It does not delay navigation, database work, or the caller's workflow.
class AppFeedback {
  static OverlayEntry? _currentEntry;

  static void success(
    BuildContext context, {
    String title = 'Successful',
    required String message,
  }) => _show(
    context,
    type: AppFeedbackType.success,
    title: title,
    message: message,
    visibleFor: const Duration(milliseconds: 1900),
  );

  static void failure(
    BuildContext context, {
    String title = 'Action unsuccessful',
    required String message,
  }) => _show(
    context,
    type: AppFeedbackType.failure,
    title: title,
    message: message,
    visibleFor: const Duration(milliseconds: 3800),
  );

  static void _show(
    BuildContext context, {
    required AppFeedbackType type,
    required String title,
    required String message,
    required Duration visibleFor,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _currentEntry?.remove();
    _currentEntry = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _AppFeedbackOverlay(
        type: type,
        title: title,
        message: message,
        visibleFor: visibleFor,
        onFinished: () {
          if (entry.mounted) entry.remove();
          if (identical(_currentEntry, entry)) _currentEntry = null;
        },
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _AppFeedbackOverlay extends StatefulWidget {
  final AppFeedbackType type;
  final String title;
  final String message;
  final Duration visibleFor;
  final VoidCallback onFinished;

  const _AppFeedbackOverlay({
    required this.type,
    required this.title,
    required this.message,
    required this.visibleFor,
    required this.onFinished,
  });

  @override
  State<_AppFeedbackOverlay> createState() => _AppFeedbackOverlayState();
}

class _AppFeedbackOverlayState extends State<_AppFeedbackOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 150),
    )..forward();
    _timer = Timer(widget.visibleFor, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    try {
      await _controller.reverse().orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted) widget.onFinished();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final successful = widget.type == AppFeedbackType.success;
    final accent = successful ? const Color(0xFF25834A) : colors.error;
    final icon = successful ? Icons.check_rounded : Icons.close_rounded;

    final animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Positioned.fill(
      child: IgnorePointer(
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Align(
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.18),
                  end: Offset.zero,
                ).animate(animation),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  label: '${widget.title}. ${widget.message}',
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 430),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.34),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x26000000),
                            blurRadius: 24,
                            offset: Offset(0, 9),
                          ),
                        ],
                      ),
                      child: ExcludeSemantics(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ScaleTransition(
                              scale: animation,
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(icon, color: accent, size: 25),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.title,
                                    style: TextStyle(
                                      color: colors.onSurface,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.message,
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      height: 1.3,
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}






















