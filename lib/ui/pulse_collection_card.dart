import 'package:flutter/material.dart';

import '../app/pulse_theme.dart';
import '../domain/audio_track.dart';
import '../domain/pulse_preferences.dart';
import 'pulse_track_artwork.dart';

class PulseCollectionCard extends StatelessWidget {
  const PulseCollectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.identity,
    required this.onTap,
    this.artworkTracks,
    this.density = PulseDensity.compact,
  });

  final String title;
  final String subtitle;
  final String identity;
  final VoidCallback onTap;
  final List<AudioTrack>? artworkTracks;
  final PulseDensity density;

  @override
  Widget build(BuildContext context) {
    final padding = switch (density) {
      PulseDensity.compact => 10.0,
      PulseDensity.standard => 12.0,
      PulseDensity.comfortable => 14.0,
    };
    final gap = switch (density) {
      PulseDensity.compact => 10.0,
      PulseDensity.standard => 12.0,
      PulseDensity.comfortable => 14.0,
    };
    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF181818)
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(pulseCardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                PulseTrackArtwork(
                  artworkTracks: artworkTracks,
                  title: title,
                  creator: identity,
                  size: constraints.maxWidth,
                  borderRadius: 9,
                ),
                SizedBox(height: gap),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                SizedBox(height: gap / 5),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.68)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
