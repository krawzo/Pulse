import 'package:flutter/material.dart';

/// A local, deterministic illustration based on catalog metadata.
/// It is intentionally not presented as embedded album art.
class PulseLocalArtwork extends StatelessWidget {
  const PulseLocalArtwork({
    super.key,
    required this.title,
    this.creator = '',
    this.icon,
    this.size = 48,
    this.borderRadius = 10,
  });

  final String title;
  final String creator;
  final IconData? icon;
  final double size;
  final double borderRadius;

  static const _palettes = [
    [Color(0xFF54D68B), Color(0xFF174838)],
    [Color(0xFFD6A66A), Color(0xFF563A34)],
    [Color(0xFF7B8BD1), Color(0xFF252F57)],
    [Color(0xFFCA7684), Color(0xFF542F43)],
    [Color(0xFF59B7B0), Color(0xFF20434A)],
    [Color(0xFFB393D2), Color(0xFF49375B)],
  ];

  @override
  Widget build(BuildContext context) {
    final identity = '$creator\u0000$title';
    final seed = _stableHash(identity);
    final palette = _palettes[seed % _palettes.length];
    final initial = title.trim().isEmpty ? '♪' : title.trim()[0].toUpperCase();
    return Semantics(
      image: true,
      label: icon == null
          ? 'Arte abstrata local para ${title.isEmpty ? 'faixa' : title}'
          : 'Ícone de ${title.isEmpty ? 'item' : title}',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: palette,
                    ),
                  ),
                ),
                CustomPaint(painter: _ArtworkPatternPainter(seed: seed)),
                Center(
                  child: icon == null
                      ? Text(
                          initial,
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: size * 0.36,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : Icon(icon,
                          size: size * .46,
                          color: Colors.white.withValues(alpha: .94)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

class _ArtworkPatternPainter extends CustomPainter {
  const _ArtworkPatternPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.035;
    final center = Offset(
      size.width * (0.28 + ((seed >> 4) & 7) / 20),
      size.height * (0.32 + ((seed >> 8) & 7) / 20),
    );
    final radius = size.shortestSide * (0.22 + ((seed >> 12) & 3) / 30);
    canvas.drawCircle(center, radius, paint);
    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.78)
      ..cubicTo(
        size.width * 0.35,
        size.height * 0.42,
        size.width * 0.62,
        size.height * 1.05,
        size.width * 0.96,
        size.height * 0.55,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArtworkPatternPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
