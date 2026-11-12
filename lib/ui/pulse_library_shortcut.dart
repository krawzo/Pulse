import 'package:flutter/material.dart';

import '../domain/audio_track.dart';
import '../domain/pulse_preferences.dart';
import 'pulse_track_artwork.dart';

class PulseLibraryShortcut extends StatelessWidget {
  const PulseLibraryShortcut({
    super.key,
    required this.title,
    required this.subtitle,
    required this.identity,
    required this.onTap,
    this.artworkTracks,
    this.largeArtwork = false,
    this.density = PulseDensity.compact,
  });

  final String title;
  final String subtitle;
  final String identity;
  final VoidCallback onTap;
  final List<AudioTrack>? artworkTracks;
  final bool largeArtwork;
  final PulseDensity density;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: '$title · $subtitle',
        child: Material(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF2A2A2A)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(4),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: (largeArtwork ? 164.0 : 64.0) +
                  switch (density) {
                    PulseDensity.compact => 0,
                    PulseDensity.standard => 8,
                    PulseDensity.comfortable => 16,
                  },
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: largeArtwork ? 8 : 0),
                child: largeArtwork
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PulseTrackArtwork(
                            artworkTracks: artworkTracks,
                            title: title,
                            creator: identity,
                            size: 104,
                            borderRadius: 8,
                          ),
                          const SizedBox(height: 6),
                          _ShortcutText(title: title, subtitle: subtitle),
                        ],
                      )
                    : Row(
                        children: [
                          PulseTrackArtwork(
                            artworkTracks: artworkTracks,
                            title: title,
                            creator: identity,
                            size: 64,
                            borderRadius: 4,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ShortcutText(
                              title: title,
                              subtitle: subtitle,
                              showSubtitle: false,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
}

class _ShortcutText extends StatelessWidget {
  const _ShortcutText(
      {required this.title, required this.subtitle, this.showSubtitle = true});

  final String title;
  final String subtitle;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$title, $subtitle',
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (showSubtitle)
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
      );
}
