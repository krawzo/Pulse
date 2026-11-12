import 'package:flutter/material.dart';

class PulseArtistLink extends StatefulWidget {
  const PulseArtistLink({
    super.key,
    required this.artist,
    required this.fallback,
    required this.style,
    required this.onOpenArtist,
    this.maxLines = 1,
    this.textAlign,
  });

  final String? artist;
  final String fallback;
  final TextStyle? style;
  final ValueChanged<String> onOpenArtist;
  final int maxLines;
  final TextAlign? textAlign;

  @override
  State<PulseArtistLink> createState() => _PulseArtistLinkState();
}

class _PulseArtistLinkState extends State<PulseArtistLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist?.trim() ?? '';
    final valid = artist.isNotEmpty;
    final label = valid ? artist : widget.fallback;
    final text = Text(
      label,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: widget.textAlign,
      style: widget.style?.copyWith(
        decoration: valid && _hovered ? TextDecoration.underline : null,
      ),
    );
    if (!valid) return text;
    return Tooltip(
      message: 'Abrir página de $artist',
      child: InkWell(
        onTap: () => widget.onOpenArtist(artist),
        onHover: (hovered) => setState(() => _hovered = hovered),
        child: text,
      ),
    );
  }
}
