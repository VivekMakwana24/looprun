import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../core/links_view_model.dart';
import '../core/widgets.dart';
import 'auth_view_model.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final TextEditingController _devName = TextEditingController(text: 'dev');

  @override
  void dispose() {
    _devName.dispose();
    super.dispose();
  }

  Future<void> _openPolicy() async {
    final links = ref.read(linksViewModelProvider);
    final opened = await links.openPrivacyPolicy();
    if (!opened && mounted) await showPrivacyPolicyFallback(context, links.privacyPolicyUrl);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final auth = ref.watch(authViewModelProvider);
    final showDev = ref.watch(devLoginVisibleProvider);
    final steps = const [
      'Run any closed loop in your city',
      'Every cell inside becomes yours',
      'Keep running it, or it fades',
    ];
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: AspectRatio(
                aspectRatio: 390 / 500,
                child: CustomPaint(
                  painter: _TrackPainter(
                    lane: c.lane,
                    accent: c.accent,
                    accentText: c.accentText,
                    text: c.text,
                    muted: c.muted,
                    bg: c.bg,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.width * 0.55),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text('LOOPRUN', style: LrText.display(84, color: c.text, tracking: 0.01, height: 0.88)),
                        ),
                        const SizedBox(height: 6),
                        Text('Run a loop. Fill the map.',
                            style: LrText.body(20, weight: FontWeight.w500, color: c.text2)),
                        const SizedBox(height: 24),
                        Container(
                          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                          child: Column(
                            children: [
                              for (var i = 0; i < steps.length; i++)
                                Container(
                                  height: 46,
                                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 18,
                                        child: Text('${i + 1}', style: LrText.display(22, color: c.accentText, height: 1)),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(child: Text(steps[i], style: LrText.body(16, color: c.text))),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        LrBox(
                          key: const Key('google_sign_in_button'),
                          onTap: auth.busy ? null : () => ref.read(authViewModelProvider.notifier).signInWithGoogle(),
                          color: c.paper,
                          radius: 22,
                          height: 62,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (auth.busy)
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: c.onPaper),
                                )
                              else
                                Icon(Icons.login, size: 22, color: c.onPaper),
                              const SizedBox(width: 12),
                              Text('Sign in with Google',
                                  style: LrText.body(18, weight: FontWeight.w600, color: c.onPaper)),
                            ],
                          ),
                        ),
                        if (auth.error != null) ...[
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              auth.error!,
                              key: const Key('sign_in_error'),
                              textAlign: TextAlign.center,
                              style: LrText.body(14, weight: FontWeight.w500, color: c.danger, height: 1.4),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('Your Google account is only used to sign you in.',
                                textAlign: TextAlign.center, style: LrText.body(13, color: c.muted)),
                            TextButton(
                              key: const Key('sign_in_privacy_link'),
                              onPressed: _openPolicy,
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                              child: Text('Privacy Policy',
                                  style: LrText.body(13,
                                      weight: FontWeight.w600, color: c.accentText, decoration: TextDecoration.underline)),
                            ),
                          ],
                        ),
                        if (showDev) ...[
                          const SizedBox(height: 12),
                          _DevLogin(
                            controller: _devName,
                            busy: auth.busy,
                            onLogin: () {
                              final name = _devName.text.trim();
                              ref.read(authViewModelProvider.notifier).signInDev(name.isEmpty ? 'dev' : name);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The secondary block for debug builds: sign in as `dev:<name>` (server needs LOOPRUN_DEV_AUTH=1).
class _DevLogin extends StatelessWidget {
  const _DevLogin({required this.controller, required this.busy, required this.onLogin});
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Container(
      key: const Key('dev_login_block'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('DEVELOPMENT LOGIN', style: LrText.label(13, color: c.muted)),
          const SizedBox(height: 2),
          Text('Debug builds only. The server must run with LOOPRUN_DEV_AUTH=1.',
              style: LrText.body(12, color: c.muted)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('dev_name_field'),
                  controller: controller,
                  style: LrText.body(16, color: c.text),
                  decoration: const InputDecoration(labelText: 'Name', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              LrBox(
                key: const Key('dev_login_button'),
                onTap: busy ? null : onLogin,
                color: c.raised,
                borderColor: c.line,
                radius: 16,
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text('Dev login', style: LrText.body(15, weight: FontWeight.w600, color: c.text)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The running track from the sign-in mockup: lanes round a bend, the accent runner on lane 2, the
/// start line and lane numbers. Drawn in a 390 x 500 box and scaled to the width.
class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.lane,
    required this.accent,
    required this.accentText,
    required this.text,
    required this.muted,
    required this.bg,
  });

  final Color lane;
  final Color accent;
  final Color accentText;
  final Color text;
  final Color muted;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final k = size.width / 390;
    canvas.scale(k);
    const centre = Offset(390, 250);
    final lanePaint = Paint()
      ..color = lane
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var r = 120.0; r <= 360; r += 40) {
      canvas.drawCircle(centre, r, lanePaint);
    }
    final arc = Rect.fromCircle(center: centre, radius: 180);
    canvas.drawArc(
      arc,
      math.pi,
      math.pi / 2,
      false,
      Paint()
        ..color = accent.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 30,
    );
    // From the start line (just below it) up the bend to the runner.
    const from = math.pi - 0.2189; // atan2(39, -175.4)
    const to = math.pi + 1.0415; // the runner at (300, 94.1)
    canvas.drawArc(
      arc,
      from,
      to - from,
      false,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    const runner = Offset(300, 94.1);
    canvas.drawCircle(runner, 9, Paint()..color = accent);
    canvas.drawCircle(
      runner,
      16,
      Paint()
        ..color = accent.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      const Offset(24, 250),
      const Offset(270, 250),
      Paint()
        ..color = text.withValues(alpha: 0.7)
        ..strokeWidth = 3,
    );
    for (var i = 0; i < 6; i++) {
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: LrText.display(20, color: i == 1 ? accentText : muted, height: 1)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(250 - i * 40 - tp.width / 2, 240 - tp.height));
    }
    canvas.restore();
    // Fade into the background at the bottom.
    final fade = Rect.fromLTWH(0, size.height * 0.68, size.width, size.height * 0.32);
    canvas.drawRect(
      fade,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg.withValues(alpha: 0), bg],
        ).createShader(fade),
    );
  }

  @override
  bool shouldRepaint(covariant _TrackPainter old) => old.accent != accent || old.lane != lane || old.bg != bg;
}
