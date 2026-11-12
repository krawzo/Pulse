import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/app/pulse_theme.dart';
import 'package:pulse_flutter/app/pulse_app_metadata.dart';
import 'package:pulse_flutter/data/local_artwork_cache.dart';
import 'package:pulse_flutter/data/windows_library_store.dart';
import 'package:pulse_flutter/domain/audio_track.dart';
import 'package:pulse_flutter/domain/library_snapshot.dart';
import 'package:pulse_flutter/domain/pulse_preferences.dart';
import 'package:pulse_flutter/state/library_controller.dart';
import 'package:pulse_flutter/state/jellyfin_controller.dart';
import 'package:pulse_flutter/state/playback_controller.dart';
import 'package:pulse_flutter/ui/compact_mini_player.dart';
import 'package:pulse_flutter/ui/pulse_home_page.dart';
import 'package:pulse_flutter/ui/pulse_now_playing_panel.dart';
import 'package:pulse_flutter/ui/pulse_navigation_widgets.dart';
import 'package:pulse_flutter/ui/pulse_desktop_library_sidebar.dart';
import 'package:pulse_flutter/ui/pulse_collection_card.dart';
import 'package:pulse_flutter/ui/pulse_queue_panel.dart';
import 'package:pulse_flutter/ui/pulse_navigation.dart';
import 'package:pulse_flutter/ui/pulse_expanded_player_view.dart';
import 'package:pulse_flutter/ui/pulse_header.dart';
import 'package:pulse_flutter/ui/pulse_settings_page.dart';
import 'package:pulse_flutter/ui/pulse_library_shortcut.dart';
import 'package:pulse_flutter/ui/pulse_track_row.dart';
import 'package:pulse_flutter/ui/pulse_track_artwork.dart';
import 'package:pulse_flutter/ui/pulse_player_dock.dart';
import 'package:pulse_flutter/ui/pulse_playback_mode_buttons.dart';

bool _reviewFontsLoaded = false;
late Directory _artworkFixtureDirectory;
late AudioTrack _embeddedArtworkTrack;

void main() {
  setUpAll(() async {
    _artworkFixtureDirectory =
        await Directory.systemTemp.createTemp('pulse-full-art-review-');
    final file = File('${_artworkFixtureDirectory.path}/album-cover.mp3');
    await file.writeAsBytes(await _embeddedPngMp3());
    final stat = await file.stat();
    _embeddedArtworkTrack = AudioTrack(
      id: 'embedded-artwork-review-track',
      path: file.path,
      title: 'Faixa com capa local',
      artist: 'Pulse Review Ensemble',
      album: 'Capa incorporada',
      sizeBytes: stat.size,
      modifiedAtMillis: stat.modified.millisecondsSinceEpoch,
    );
    await LocalArtworkCache.instance.imageFor(
      file.path,
      stat.size,
      stat.modified.millisecondsSinceEpoch,
    );
  });

  tearDownAll(() async {
    if (await _artworkFixtureDirectory.exists()) {
      await _artworkFixtureDirectory.delete(recursive: true);
    }
  });

  testWidgets('embedded album artwork appears on compact and desktop', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    final library = _ReviewLibraryController(
      snapshot: LibrarySnapshot(
        rootPath: r'C:\Review fixtures\Music',
        tracks: [_embeddedArtworkTrack],
      ),
    );
    final playback = _ReviewPlaybackController(
      track: _embeddedArtworkTrack,
      isPlaying: true,
      position: const Duration(seconds: 24),
      duration: const Duration(minutes: 2, seconds: 16),
    );
    addTearDown(library.dispose);
    addTearDown(playback.dispose);

    for (final width in [360, 1280]) {
      await _pumpPulsePage(
        tester,
        width: width,
        library: library,
        playback: playback,
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      if (width == 360) {
        final shortcut = tester.widget<PulseLibraryShortcut>(
          find.widgetWithText(PulseLibraryShortcut, 'Capa incorporada'),
        );
        expect(
          shortcut.artworkTracks!.map((item) => item.id),
          [_embeddedArtworkTrack.id],
        );
        expect(
          find.descendant(
            of: find.widgetWithText(PulseLibraryShortcut, 'Capa incorporada'),
            matching: find.byType(Image),
          ),
          findsOneWidget,
        );
        expect(
          tester.getSize(
            find.descendant(
              of: find.widgetWithText(PulseLibraryShortcut, 'Capa incorporada'),
              matching: find.byType(Image),
            ),
          ),
          const Size(104, 104),
        );
        expect(
          find.descendant(
            of: find.widgetWithText(PulseLibraryShortcut, 'Capa incorporada'),
            matching: find.text('C'),
          ),
          findsNothing,
        );
      }
      await _capture(tester, 'goldens/pulse_artwork_home_${width}x800.png');
      if (width == 360) {
        await tester.tap(find.widgetWithText(ChoiceChip, 'Álbuns'));
      } else {
        await tester.tap(find.text('Álbuns').first);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Capa incorporada'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Faixa com capa local'), findsAtLeastNWidgets(1));
      await _capture(tester, 'goldens/pulse_artwork_album_${width}x800.png');
    }
  });

  testWidgets(
    'populated three-panel and expanded-player review in both themes',
    (tester) async {
      await _prepareReviewTest(tester);
      final tracks = [
        _embeddedArtworkTrack,
        ..._denseReviewTracks().take(16),
      ];
      final cover = await tester.runAsync(
        () => LocalArtworkCache.instance.imageFor(
          _embeddedArtworkTrack.path,
          _embeddedArtworkTrack.sizeBytes,
          _embeddedArtworkTrack.modifiedAtMillis,
        ),
      );
      expect(cover, isNotNull);

      for (final size in const [
        (width: 840, height: 800),
        (width: 1280, height: 800),
        (width: 1920, height: 1080),
      ]) {
        for (final appearance in PulseAppearance.values) {
          final library = _ReviewLibraryController(
            snapshot: LibrarySnapshot(
              rootPath: r'C:\Review fixtures\Music',
              tracks: tracks,
              favoriteIds: {_embeddedArtworkTrack.id},
              playlists: const [
                PulsePlaylist(
                  id: 'review-mix',
                  name: 'Mix local de revisão',
                  trackIds: ['embedded-artwork-review-track'],
                ),
              ],
            ),
          );
          final playback = _ReviewPlaybackController(
            track: _embeddedArtworkTrack,
            isPlaying: true,
            position: const Duration(minutes: 1, seconds: 12),
            duration: const Duration(minutes: 3, seconds: 40),
          );
          addTearDown(library.dispose);
          addTearDown(playback.dispose);

          await _pumpPulsePage(
            tester,
            width: size.width,
            height: size.height,
            library: library,
            playback: playback,
            appearance: appearance,
            reviewKey: 'populated-${appearance.name}',
          );
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          expect(find.text('Faixa com capa local'), findsAtLeastNWidgets(1));
          expect(find.byType(Image), findsAtLeastNWidgets(1));
          if (size.width >= 1200) {
            final dock = find.byType(PulsePlayerDock);
            final slider = find.descendant(
              of: dock,
              matching: find.byType(Slider),
            );
            expect(tester.getSize(slider.first).width, lessThanOrEqualTo(680));
            expect(tester.getRect(slider.first).center.dx,
                closeTo(tester.getRect(dock).center.dx, 1));
          }
          if (size.width == 840) {
            final sidebar = find.byType(PulseExpandedSidebar);
            for (final label in const ['Biblioteca', 'Favoritos']) {
              final text = find.descendant(
                of: sidebar,
                matching: find.text(label),
              );
              expect(text, findsOneWidget);
              expect(
                tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
                isFalse,
                reason: '$label must fit at 840 dp',
              );
            }
          } else {
            expect(find.byType(PulseNowPlayingPanel), findsOneWidget);
            final artwork = find.descendant(
              of: find.byType(PulseNowPlayingPanel),
              matching: find.byType(PulseTrackArtwork),
            );
            final artworkSize = tester.getSize(artwork);
            expect(artworkSize.width, closeTo(artworkSize.height, 1.5));
            expect(
              artworkSize.width,
              closeTo(size.width == 1280 ? 240 : 360, 5),
            );
          }
          await _capture(
            tester,
            'goldens/pulse_populated_${size.width}x${size.height}_${appearance.name}.png',
          );

          if (size.width == 1280) {
            await tester.tap(find.byType(TextField).first);
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<TextField>(find.byType(TextField).first)
                  .focusNode!
                  .hasFocus,
              isTrue,
            );
            await _capture(
              tester,
              'goldens/pulse_search_focused_1280x800_${appearance.name}.png',
            );
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
          }

          if (size.width >= 1280) {
            Focus.of(tester
                    .element(find.byKey(const ValueKey('now-playing-header'))))
                .requestFocus();
            await tester.pumpAndSettle();
            await tester.tap(
              find.descendant(
                of: find.byType(PulseNowPlayingPanel),
                matching: find.byTooltip('Entrar na tela cheia'),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(PulseExpandedPlayerView), findsOneWidget);
            await _capture(
              tester,
              'goldens/pulse_expanded_${size.width}x${size.height}_${appearance.name}.png',
            );
          }
        }
      }
    },
  );

  testWidgets('single header toggle opens and hides the right panel', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    final tracks = [_embeddedArtworkTrack, ..._denseReviewTracks().take(16)];
    for (final size in const [
      (width: 1120, height: 800),
      (width: 1200, height: 800),
      (width: 1280, height: 800),
      (width: 1920, height: 1080),
    ]) {
      for (final appearance in PulseAppearance.values) {
        final library = _ReviewLibraryController(
          snapshot: LibrarySnapshot(
            rootPath: r'C:\Review fixtures\Music',
            tracks: tracks,
          ),
        );
        final playback =
            _ReviewPlaybackController(track: _embeddedArtworkTrack);
        addTearDown(library.dispose);
        addTearDown(playback.dispose);
        await _pumpPulsePage(
          tester,
          width: size.width,
          height: size.height,
          library: library,
          playback: playback,
          appearance: appearance,
          reviewKey: 'panel-toggle-${appearance.name}',
        );
        expect(find.byType(PulseNowPlayingPanel), findsOneWidget);
        expect(find.byTooltip('Ocultar a tela Tocando agora'), findsNothing);
        expect(find.byTooltip('Recolher painel Tocando agora'), findsNothing);
        await _capture(
          tester,
          'goldens/pulse_panel_open_${size.width}x${size.height}_${appearance.name}.png',
        );

        final header = find.byKey(const ValueKey('now-playing-header'));
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        await mouse.addPointer();
        await mouse.moveTo(tester.getCenter(header));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Ocultar a tela Tocando agora'), findsOneWidget);
        await tester.tap(find.byTooltip('Ocultar a tela Tocando agora'));
        await tester.pumpAndSettle();
        expect(find.byType(PulseNowPlayingPanel), findsNothing);
        expect(find.byTooltip('Mostrar a tela Tocando agora'), findsOneWidget);
        expect(
          tester
              .widget<Icon>(find.descendant(
                of: find.byTooltip('Mostrar a tela Tocando agora'),
                matching: find.byType(Icon),
              ))
              .icon,
          Icons.keyboard_double_arrow_left_rounded,
        );
        await _capture(
          tester,
          'goldens/pulse_panel_closed_${size.width}x${size.height}_${appearance.name}.png',
        );

        await tester.tap(find.byTooltip('Mostrar a tela Tocando agora'));
        await tester.pumpAndSettle();
        expect(find.byType(PulseNowPlayingPanel), findsOneWidget);
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Ocultar a tela Tocando agora'), findsNothing);
        await mouse.removePointer();
      }
    }
  });

  testWidgets('Now Playing header reveals actions on hover and keyboard focus',
      (tester) async {
    await _prepareReviewTest(tester);
    const title =
        'Uma faixa local com um título longo para verificar o corte no cabeçalho do painel Tocando agora';
    final track = AudioTrack(
      id: 'long-header-track',
      path: _embeddedArtworkTrack.path,
      title: title,
      artist: 'Pulse Review Ensemble',
      album: 'Capa incorporada',
      sizeBytes: _embeddedArtworkTrack.sizeBytes,
      modifiedAtMillis: _embeddedArtworkTrack.modifiedAtMillis,
    );
    final library = _ReviewLibraryController(
      snapshot: LibrarySnapshot(
        rootPath: r'C:\Review fixtures\Music',
        tracks: [track],
        playlists: const [
          PulsePlaylist(id: 'review-mix', name: 'Mix local', trackIds: []),
        ],
      ),
    );
    final playback = _ReviewPlaybackController(track: track, isPlaying: true);
    addTearDown(library.dispose);
    addTearDown(playback.dispose);

    for (final size in const [
      (width: 1280, height: 800),
      (width: 1920, height: 1080),
    ]) {
      await _pumpPulsePage(
        tester,
        width: size.width,
        height: size.height,
        library: library,
        playback: playback,
        reviewKey: 'now-playing-header',
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final header = find.byKey(const ValueKey('now-playing-header'));
      final headerTitle = find.descendant(
        of: header,
        matching: find.text(title),
      );
      expect(headerTitle, findsOneWidget);
      expect(tester.widget<Text>(headerTitle).maxLines, 1);
      expect(tester.widget<Text>(headerTitle).overflow, TextOverflow.ellipsis);
      expect(
          tester.renderObject<RenderParagraph>(headerTitle).didExceedMaxLines,
          isTrue);
      expect(find.byTooltip('Ocultar a tela Tocando agora'), findsNothing);
      expect(
          find.descendant(of: header, matching: find.byTooltip('Mais opções')),
          findsNothing);
      expect(
          find.descendant(
              of: header, matching: find.byTooltip('Entrar na tela cheia')),
          findsNothing);
      final titleRect = tester.getRect(headerTitle);
      await _capture(tester,
          'goldens/pulse_now_playing_header_normal_${size.width}x${size.height}_dark.png');

      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(header));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ocultar a tela Tocando agora'), findsOneWidget);
      expect(
          find.descendant(of: header, matching: find.byTooltip('Mais opções')),
          findsOneWidget);
      expect(
          find.descendant(
              of: header, matching: find.byTooltip('Entrar na tela cheia')),
          findsOneWidget);
      expect(tester.getRect(headerTitle), titleRect);
      await _capture(tester,
          'goldens/pulse_now_playing_header_hover_${size.width}x${size.height}_dark.png');

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ocultar a tela Tocando agora'), findsNothing);
      tester
          .widget<TextField>(find.byType(TextField).first)
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      var reachedHeaderByTab = false;
      for (var tab = 0; tab < 80; tab++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        if (Focus.of(tester.element(header)).hasFocus) {
          reachedHeaderByTab = true;
          break;
        }
      }
      expect(reachedHeaderByTab, isTrue);
      expect(find.byTooltip('Ocultar a tela Tocando agora'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(Focus.of(tester.element(header)).hasFocus, isTrue);
      expect(tester.getRect(headerTitle), titleRect);
      await _capture(tester,
          'goldens/pulse_now_playing_header_focus_${size.width}x${size.height}_dark.png');
      var leftHeaderByTab = false;
      for (var tab = 0; tab < 8; tab++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        if (!Focus.of(tester.element(header)).hasFocus) {
          leftHeaderByTab = true;
          break;
        }
      }
      expect(leftHeaderByTab, isTrue);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ocultar a tela Tocando agora'), findsNothing);
      await mouse.moveTo(tester.getCenter(header));
      await tester.pumpAndSettle();
      await tester.tap(
          find.descendant(of: header, matching: find.byTooltip('Mais opções')));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar a Mix local'), findsOneWidget);
      await tester.tap(find.text('Adicionar a Mix local'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    }
  });

  testWidgets(
      'right panel resize respects minimum, default maximum and window changes',
      (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    for (final width in [1120, 1280, 1920]) {
      final library = _ReviewLibraryController(
        snapshot: LibrarySnapshot(
          rootPath: r'C:\Review fixtures\Music',
          tracks: [_embeddedArtworkTrack],
        ),
      );
      final playback = _ReviewPlaybackController(track: _embeddedArtworkTrack);
      addTearDown(library.dispose);
      addTearDown(playback.dispose);
      await _pumpPulsePage(
        tester,
        width: width,
        height: width == 1920 ? 1080 : 800,
        library: library,
        playback: playback,
        reviewKey: 'panel-resize',
      );
      final handle = find.byKey(const ValueKey('now-playing-resize-handle'));
      final panel = find.byType(PulseNowPlayingPanel);
      expect(handle, findsOneWidget);
      expect(tester.getSize(handle).width, 12);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: panel, matching: find.byType(Image)),
        findsOneWidget,
      );
      final defaultWidth = tester.getSize(panel).width;
      final minimum = width >= 1440 ? 320.0 : 240.0;

      await tester.drag(handle, const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, minimum);
      expect(tester.takeException(), isNull);
      if (width == 1280) {
        await _capture(
          tester,
          'goldens/pulse_panel_resized_min_1280x800_dark.png',
        );
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(0, 0));
        await mouse.moveTo(tester.getCenter(handle));
        await tester.pumpAndSettle();
        await _capture(
          tester,
          'goldens/pulse_panel_handle_hover_1280x800_dark.png',
        );
        await mouse.moveTo(
          tester.getBottomLeft(handle) + const Offset(6, -20),
        );
        await tester.pumpAndSettle();
        await _capture(
          tester,
          'goldens/pulse_panel_handle_tooltip_1280x800_dark.png',
        );
        await mouse.removePointer();
        await tester.pumpAndSettle();
      } else if (width == 1920) {
        await _capture(
          tester,
          'goldens/pulse_panel_resized_min_1920x1080_dark.png',
        );
      }

      await tester.drag(handle, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, closeTo(defaultWidth, 1));

      await tester.tap(handle);
      await tester.pumpAndSettle();
      if (width == 1280) {
        await _capture(
          tester,
          'goldens/pulse_panel_handle_focus_1280x800_dark.png',
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, closeTo(defaultWidth - 16, 1));

      if (width == 1920) {
        tester.view.physicalSize = const Size(1280, 800);
        await tester.pumpAndSettle();
        expect(tester.getSize(panel).width, 280);
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(1920, 1080);
        await tester.pumpAndSettle();
        expect(tester.getSize(panel).width, closeTo(defaultWidth - 16, 1));
        tester.view.physicalSize = const Size(840, 800);
        await tester.pumpAndSettle();
        expect(handle, findsNothing);
        expect(panel, findsNothing);
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(1920, 1080);
        await tester.pumpAndSettle();
        expect(tester.getSize(panel).width, closeTo(defaultWidth - 16, 1));
      }
    }
  });

  testWidgets('left sidebar resize preserves right panel and restores width',
      (tester) async {
    await _prepareReviewTest(tester);
    final library = _ReviewLibraryController(
      snapshot: LibrarySnapshot(
        rootPath: r'C:\Review fixtures\Music',
        tracks: [_embeddedArtworkTrack],
      ),
    );
    final playback = _ReviewPlaybackController(track: _embeddedArtworkTrack);
    addTearDown(library.dispose);
    addTearDown(playback.dispose);

    for (final (width, minWidth) in [
      (840, 160.0),
      (1120, 200.0),
      (1280, 280.0),
      (1920, 300.0),
    ]) {
      await _pumpPulsePage(tester,
          width: width,
          height: width == 1920 ? 1080 : 800,
          library: library,
          playback: playback,
          reviewKey: 'left-resize-$width');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey('sidebar-resize-handle'));
      final sidebar = width >= 1120
          ? find.byType(PulseDesktopLibrarySidebar)
          : find.byType(PulseExpandedSidebar);
      final panel = find.byType(PulseNowPlayingPanel);
      expect(handle, findsOneWidget);
      expect(tester.getSize(handle).width, 12);
      final defaultWidth = tester.getSize(sidebar).width;
      final rightWidth =
          panel.evaluate().isEmpty ? null : tester.getSize(panel).width;

      await tester.drag(handle, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, minWidth);
      if (rightWidth != null) expect(tester.getSize(panel).width, rightWidth);
      final centerWidth =
          width - minWidth - (rightWidth ?? 0) - (rightWidth == null ? 24 : 32);
      expect(
          centerWidth,
          greaterThanOrEqualTo(width >= 1440
              ? 640
              : width >= 1120
                  ? 560
                  : 600));
      expect(tester.takeException(), isNull);
      if (width == 1280 || width == 1920) {
        await _capture(tester,
            'goldens/pulse_sidebar_resized_min_${width.toInt()}x${width == 1920 ? 1080 : 800}_dark.png');
      }
      if (width == 1280) {
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(0, 0));
        await mouse.moveTo(tester.getCenter(handle));
        await tester.pumpAndSettle();
        await _capture(
            tester, 'goldens/pulse_sidebar_handle_hover_1280x800_dark.png');
        await mouse.removePointer();
      }

      await tester.drag(handle, const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, closeTo(defaultWidth, 1));
      if (rightWidth != null) expect(tester.getSize(panel).width, rightWidth);
      await tester.tap(handle);
      if (width == 1280) {
        await _capture(
            tester, 'goldens/pulse_sidebar_handle_focus_1280x800_dark.png');
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width,
          closeTo((defaultWidth - 16).clamp(minWidth, defaultWidth), 1));
      if (rightWidth != null) expect(tester.getSize(panel).width, rightWidth);
      expect(tester.takeException(), isNull);

      if (width == 1920) {
        tester.view.physicalSize = const Size(720, 800);
        await tester.pumpAndSettle();
        expect(handle, findsNothing);
        tester.view.physicalSize = const Size(1920, 1080);
        await tester.pumpAndSettle();
        expect(tester.getSize(sidebar).width, closeTo(defaultWidth - 16, 1));
      }
    }
  });

  testWidgets('light panel resize handle remains visible on hover and focus', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    final library = _ReviewLibraryController(
      snapshot: LibrarySnapshot(
        rootPath: r'C:\Review fixtures\Music',
        tracks: [_embeddedArtworkTrack],
      ),
    );
    final playback = _ReviewPlaybackController(track: _embeddedArtworkTrack);
    addTearDown(library.dispose);
    addTearDown(playback.dispose);
    await _pumpPulsePage(
      tester,
      width: 1280,
      library: library,
      playback: playback,
      appearance: PulseAppearance.light,
      reviewKey: 'light-panel-resize',
    );
    final handle = find.byKey(const ValueKey('now-playing-resize-handle'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PulseNowPlayingPanel),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 0));
    await mouse.moveTo(tester.getCenter(handle));
    await tester.pumpAndSettle();
    await _capture(
      tester,
      'goldens/pulse_panel_handle_hover_1280x800_light.png',
    );
    await mouse.removePointer();
    await tester.tap(handle);
    await tester.pumpAndSettle();
    await _capture(
      tester,
      'goldens/pulse_panel_handle_focus_1280x800_light.png',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PulseNowPlayingPanel)).width, 264);
  });

  testWidgets('expanded player keeps dock, search, track and scroll position', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    final tracks = _denseReviewTracks();
    final library = _ReviewLibraryController(
      snapshot: LibrarySnapshot(
        rootPath: r'C:\Review fixtures\Music',
        tracks: tracks,
      ),
    );
    final playback = _ReviewPlaybackController(
      track: tracks.first,
      isPlaying: true,
      position: const Duration(minutes: 1),
      duration: const Duration(minutes: 3),
    );
    addTearDown(library.dispose);
    addTearDown(playback.dispose);
    await _pumpPulsePage(
      tester,
      width: 1280,
      library: library,
      playback: playback,
      reviewKey: 'expand-state',
    );
    await tester.tap(find.descendant(
      of: find.byType(PulseDesktopLibrarySidebar),
      matching: find.text('Faixas'),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Synthetic');
    await tester.pumpAndSettle();
    final tracksList = find
        .ancestor(
          of: find.byType(PulseTrackRow).first,
          matching: find.byType(ListView),
        )
        .first;
    final scrollable = find.descendant(
      of: tracksList,
      matching: find.byType(Scrollable),
    );
    await tester.drag(tracksList, const Offset(0, -320));
    await tester.pumpAndSettle();
    final offsetBefore =
        tester.state<ScrollableState>(scrollable).position.pixels;
    expect(offsetBefore, greaterThan(0));
    final dockBefore = tester.state(find.byType(PulsePlayerDock));
    final dockHeightBefore =
        tester.getSize(find.byType(PulsePlayerDock)).height;
    final normalToggle = find.descendant(
      of: find.byType(PulsePlayerDock),
      matching: find.byTooltip('Entrar na tela cheia'),
    );
    final toggleRectBefore = tester.getRect(normalToggle);
    expect(
      tester
          .widget<Icon>(find.descendant(
            of: normalToggle,
            matching: find.byType(Icon),
          ))
          .icon,
      Icons.open_in_full_rounded,
    );

    await tester.tap(normalToggle);
    await tester.pumpAndSettle();
    expect(find.byType(PulseExpandedPlayerView), findsOneWidget);
    expect(find.text('Sair da tela cheia'), findsOneWidget);
    expect(find.byTooltip('Sair da tela cheia'), findsOneWidget);
    expect(find.byType(PulseHeader), findsNothing);
    expect(find.byType(PulseDesktopLibrarySidebar), findsNothing);
    expect(find.byType(PulseNowPlayingPanel), findsNothing);
    expect(
        tester.getSize(find.byType(PulsePlayerDock)).height, dockHeightBefore);
    final expandedToggle = find.descendant(
      of: find.byType(PulsePlayerDock),
      matching: find.byTooltip('Sair da tela cheia'),
    );
    expect(tester.getRect(expandedToggle), toggleRectBefore);
    expect(
      tester
          .widget<Icon>(find.descendant(
            of: expandedToggle,
            matching: find.byType(Icon),
          ))
          .icon,
      Icons.close_fullscreen_rounded,
    );
    expect(find.byType(PulsePlaybackModeButtons), findsOneWidget);
    expect(find.byTooltip('Fila de reprodução'), findsOneWidget);
    expect(find.byType(Slider), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Sair da tela cheia'));
    await tester.pumpAndSettle();
    expect(find.byType(PulseExpandedPlayerView), findsNothing);
    expect(tester.state(find.byType(PulsePlayerDock)), same(dockBefore));
    expect(tester.state<ScrollableState>(scrollable).position.pixels,
        closeTo(offsetBefore, 1));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Synthetic');
    expect(
        tester
            .widget<PulseDesktopLibrarySidebar>(
                find.byType(PulseDesktopLibrarySidebar))
            .selected,
        PulseDestination.tracks);
    expect(playback.currentTrack?.id, tracks.first.id);
    expect(playback.position, const Duration(minutes: 1));

    await tester.tap(find.descendant(
      of: find.byType(PulsePlayerDock),
      matching: find.byTooltip('Entrar na tela cheia'),
    ));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PulseExpandedPlayerView), findsNothing);
    expect(tester.state<ScrollableState>(scrollable).position.pixels,
        closeTo(offsetBefore, 1));
  });

  testWidgets('compact Now Playing sheet and expanded player can both close', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    for (final width in [360, 720, 840]) {
      final library = _ReviewLibraryController(
        snapshot: LibrarySnapshot(
          rootPath: r'C:\Review fixtures\Music',
          tracks: [_embeddedArtworkTrack],
        ),
      );
      final playback = _ReviewPlaybackController(track: _embeddedArtworkTrack);
      addTearDown(library.dispose);
      addTearDown(playback.dispose);
      await _pumpPulsePage(
        tester,
        width: width,
        library: library,
        playback: playback,
        reviewKey: 'compact-sheet',
      );
      final dockFinder = width >= 840
          ? find.byType(PulsePlayerDock)
          : find.byType(CompactMiniPlayer);
      final dockRectBefore = tester.getRect(dockFinder);

      await tester.tap(find.byTooltip('Mostrar a tela Tocando agora').first);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Image)),
        findsOneWidget,
      );
      await _capture(
        tester,
        'goldens/pulse_now_playing_${width}x800_dark.png',
      );
      await tester.tapAt(const Offset(100, 10));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.byTooltip('Mostrar a tela Tocando agora').first);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byTooltip('Entrar na tela cheia'),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(PulseExpandedPlayerView), findsOneWidget);
      expect(find.text('Sair da tela cheia'), findsOneWidget);
      expect(find.byType(PulseHeader), findsNothing);
      expect(find.byType(PulseExpandedSidebar), findsNothing);
      expect(find.byType(PulseNowPlayingPanel), findsNothing);
      expect(find.byType(NavigationBar),
          width < 600 ? findsOneWidget : findsNothing);
      expect(find.byType(CompactMiniPlayer),
          width < 840 ? findsOneWidget : findsNothing);
      expect(find.byType(PulsePlayerDock),
          width >= 840 ? findsOneWidget : findsNothing);
      expect(tester.getRect(dockFinder), dockRectBefore);
      await _capture(
        tester,
        'goldens/pulse_expanded_${width}x800_dark.png',
      );

      await tester.tap(find.text('Sair da tela cheia'));
      await tester.pumpAndSettle();
      expect(find.byType(PulseExpandedPlayerView), findsNothing);
      expect(playback.currentTrack?.id, _embeddedArtworkTrack.id);

      await tester.tap(find.byTooltip('Mostrar a tela Tocando agora').first);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byTooltip('Entrar na tela cheia'),
      ));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PulseExpandedPlayerView), findsNothing);
      expect(find.byType(PulseHomePage), findsOneWidget);
    }
  });

  testWidgets('settings flow fits compact and desktop and applies theme', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    final library = _ReviewLibraryController();
    final playback = _ReviewPlaybackController();
    addTearDown(library.dispose);
    addTearDown(playback.dispose);

    for (final width in [360, 1280]) {
      await _pumpPulsePage(tester,
          width: width, library: library, playback: playback);
      await tester.tap(find.byTooltip('Configurações').first);
      await tester.pumpAndSettle();
      expect(find.byType(PulseSettingsPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsNWidgets(width < 600 ? 1 : 0));
      expect(find.byType(PulsePlayerDock), findsNWidgets(width >= 840 ? 1 : 0));
      await _capture(tester, 'goldens/pulse_settings_index_${width}x800.png');

      await tester.tap(find.widgetWithText(ListTile, 'Biblioteca').last);
      await tester.pumpAndSettle();
      expect(find.text('Pasta da biblioteca'), findsOneWidget);
      await _capture(tester, 'goldens/pulse_settings_library_${width}x800.png');
      if (width < 840) {
        await tester
            .tap(find.widgetWithText(TextButton, 'Configurações').first);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Reprodução').first);
      await tester.pumpAndSettle();
      expect(find.text('Continuar de onde parei'), findsOneWidget);
      await _capture(
          tester, 'goldens/pulse_settings_playback_${width}x800.png');
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<SwitchListTile>(find.byType(SwitchListTile).first)
              .value,
          isFalse);

      if (width < 840) {
        await tester
            .tap(find.widgetWithText(TextButton, 'Configurações').first);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Armazenamento').first);
      await tester.pumpAndSettle();
      await _capture(tester, 'goldens/pulse_settings_storage_${width}x800.png');
      await tester.tap(find.text('Limpar cache de capas'));
      await tester.pumpAndSettle();
      expect(find.text('Cache de capas limpo.'), findsOneWidget);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
      if (width < 840) {
        await tester
            .tap(find.widgetWithText(TextButton, 'Configurações').first);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Sobre').first);
      await tester.pumpAndSettle();
      expect(find.text('$pulseAppVersion • build $pulseAppBuildNumber'),
          findsOneWidget);
      await _capture(tester, 'goldens/pulse_settings_about_${width}x800.png');
      if (width < 840) {
        await tester
            .tap(find.widgetWithText(TextButton, 'Configurações').first);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Aparência').first);
      await tester.pumpAndSettle();
      expect(find.byType(SegmentedButton<PulseAppearance>), findsOneWidget);
      await _capture(
          tester, 'goldens/pulse_settings_appearance_dark_${width}x800.png');
      await tester.tap(find.text('Claro'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(
          tester, 'goldens/pulse_settings_appearance_light_${width}x800.png');
      await tester.tap(find.byTooltip('Voltar à biblioteca'));
      await tester.pumpAndSettle();
      await _capture(tester, 'goldens/pulse_home_theme_light_${width}x800.png');
    }
  });

  testWidgets('four palettes render in both themes and remain selectable',
      (tester) async {
    await _prepareReviewTest(tester);
    for (final appearance in PulseAppearance.values) {
      for (final width in [360, 1280]) {
        final library = _ReviewLibraryController();
        final playback = _ReviewPlaybackController();
        addTearDown(library.dispose);
        addTearDown(playback.dispose);
        await _pumpPulsePage(
          tester,
          width: width,
          library: library,
          playback: playback,
          appearance: appearance,
          reviewKey: 'palette-settings-${appearance.name}',
        );
        await tester.tap(find.byTooltip('Configurações').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Aparência').first);
        await tester.pumpAndSettle();
        expect(find.byType(SegmentedButton<PulseAppearance>), findsOneWidget);
        for (final palette in PulsePalette.values) {
          expect(
              find.byKey(ValueKey('palette-${palette.name}')), findsOneWidget);
        }
        await _capture(tester,
            'goldens/pulse_palettes_appearance_${width}x800_${appearance.name}_top.png');
        if (width == 360) {
          await tester.ensureVisible(
              find.byKey(const ValueKey('palette-purpleDeepBlue')));
          await tester.pumpAndSettle();
          await _capture(tester,
              'goldens/pulse_palettes_appearance_360x800_${appearance.name}_bottom.png');
        }
        if (width == 1280 && appearance == PulseAppearance.dark) {
          final mouse =
              await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          await mouse.addPointer();
          for (final palette in PulsePalette.values) {
            final card = find.byKey(ValueKey('palette-${palette.name}'));
            await mouse.moveTo(tester.getCenter(card));
            await tester.pumpAndSettle();
            await _capture(tester,
                'goldens/pulse_palette_card_hover_${palette.name}_1280x800_dark.png');
            await mouse.moveTo(Offset.zero);
            await tester.pumpAndSettle();
            final focusNode = tester.widget<InkWell>(card).focusNode!;
            focusNode.requestFocus();
            await tester.pumpAndSettle();
            expect(focusNode.hasFocus, isTrue);
            await _capture(tester,
                'goldens/pulse_palette_card_focus_${palette.name}_1280x800_dark.png');
            focusNode.unfocus();
            await tester.pumpAndSettle();
          }
          await mouse.removePointer();
        }
        for (final palette in PulsePalette.values) {
          final card = find.byKey(ValueKey('palette-${palette.name}'));
          await tester.ensureVisible(card);
          await tester.pumpAndSettle();
          await tester.tap(card);
          await tester.pumpAndSettle();
          expect(
              tester
                  .widget<PulseSettingsPage>(find.byType(PulseSettingsPage))
                  .preferences
                  .palette,
              palette);
          expect(PulsePaletteTheme.of(tester.element(card)).palette, palette);
          if (width == 1280) {
            await _capture(tester,
                'goldens/pulse_palette_selected_${palette.name}_${appearance.name}_1280x800.png');
          }
        }
      }
    }

    const paletteTrack = AudioTrack(
      id: 'palette-review-track',
      path: r'C:\Review fixtures\Music\palette-review.mp3',
      title: 'Faixa de revisão',
      artist: 'Pulse local',
      sizeBytes: 1,
      modifiedAtMillis: 1,
    );
    for (final palette in PulsePalette.values) {
      for (final appearance in PulseAppearance.values) {
        final library = _ReviewLibraryController(
          snapshot: LibrarySnapshot(
            rootPath: r'C:\Review fixtures\Music',
            tracks: [paletteTrack],
          ),
        );
        final playback = _ReviewPlaybackController(
          track: paletteTrack,
          isPlaying: true,
        );
        addTearDown(library.dispose);
        addTearDown(playback.dispose);
        for (final width in [1280, 1920]) {
          await _pumpPulsePage(
            tester,
            width: width,
            height: width == 1920 ? 1080 : 800,
            library: library,
            playback: playback,
            appearance: appearance,
            palette: palette,
            reviewKey: 'palette-${palette.name}-${appearance.name}',
          );
          await tester.pumpAndSettle();
          expect(
            PulsePaletteTheme.of(tester.element(find.byType(PulseHomePage)))
                .palette,
            palette,
          );
          final shellColors =
              PulsePaletteTheme.of(tester.element(find.byType(PulseHomePage)));
          final headerMaterial = find.descendant(
              of: find.byType(PulseHeader), matching: find.byType(Material));
          final dockSurface =
              find.byKey(const Key('pulse-player-dock-surface'));
          expect(tester.widget<Material>(headerMaterial.first).color,
              shellColors.dock);
          expect(tester.widget<Container>(dockSurface).color, shellColors.dock);
          expect(
              tester
                  .widget<Scaffold>(find.byType(Scaffold).first)
                  .backgroundColor,
              shellColors.dock);
          await _capture(
            tester,
            width == 1280
                ? 'goldens/pulse_palette_library_${palette.name}_${appearance.name}_1280x800.png'
                : 'goldens/pulse_palette_shell_${palette.name}_${appearance.name}_1920x1080.png',
          );
        }
      }
    }
  });

  testWidgets('player shell follows the visual contract at all breakpoints', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    const track = AudioTrack(
      id: 'contract-selected-track',
      path: r'C:\Review fixtures\Music\selected.mp3',
      title: 'Faixa selecionada',
      artist: 'Artista de revisão',
      album: 'Álbum local',
      sizeBytes: 1000,
      modifiedAtMillis: 1,
    );

    for (final width in [360, 600, 720, 840, 1280]) {
      for (final appearance in PulseAppearance.values) {
        final library = _ReviewLibraryController(
          snapshot: const LibrarySnapshot(
            rootPath: r'C:\Review fixtures\Music',
            tracks: [track],
          ),
        );
        final playback = _ReviewPlaybackController(
          track: track,
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 3),
        );
        addTearDown(library.dispose);
        addTearDown(playback.dispose);

        await _pumpPulsePage(
          tester,
          width: width,
          library: library,
          playback: playback,
          appearance: appearance,
        );
        final expectedCanvas = appearance == PulseAppearance.light
            ? pulseLightBackground
            : pulseCanvasSurface;
        expect(
            tester
                .widget<Scaffold>(find.byType(Scaffold).first)
                .backgroundColor,
            expectedCanvas);
        final headerMaterial = find.descendant(
            of: find.byType(PulseHeader), matching: find.byType(Material));
        expect(tester.widget<Material>(headerMaterial.first).color,
            expectedCanvas);
        final settingsInHeader = find.descendant(
          of: find.byType(PulseHeader),
          matching: find.byTooltip('Configurações'),
        );
        expect(
          settingsInHeader,
          width < 600 || width >= 840 ? findsOneWidget : findsNothing,
        );
        if (width >= 600 && width < 840) {
          expect(find.byTooltip('Configurações'), findsOneWidget);
        }
        if (width >= 840) {
          expect(find.byTooltip('Configurações'), findsOneWidget);
        }
        final selectedRow = find.byWidgetPredicate(
          (widget) => widget is PulseTrackRow && widget.selected,
        );
        expect(selectedRow, findsOneWidget);
        final rowMaterial = tester.widget<Material>(
          find
              .descendant(
                of: selectedRow,
                matching: find.byType(Material),
              )
              .first,
        );
        expect(
          rowMaterial.color,
          appearance == PulseAppearance.light
              ? pulseLightSelected
              : pulseSelectedSurface,
        );
        final selectedTitle = tester.widget<Text>(
          find.descendant(of: selectedRow, matching: find.text(track.title)),
        );
        final selectedArtist = tester.widget<Text>(
          find.descendant(of: selectedRow, matching: find.text(track.artist!)),
        );
        expect(
          selectedTitle.style?.color,
          appearance == PulseAppearance.light ? pulseBackground : pulseDarkText,
        );
        expect(
          selectedArtist.style?.color,
          appearance == PulseAppearance.light ? pulseBackground : pulseDarkText,
        );
        if (width >= 840) {
          final dock = find.byType(PulsePlayerDock);
          expect(dock, findsOneWidget);
          final settingsX =
              tester.getCenter(find.byTooltip('Configurações')).dx;
          final backX = tester.getCenter(find.byTooltip('Voltar')).dx;
          final forwardX = tester.getCenter(find.byTooltip('Avançar')).dx;
          expect(settingsX, greaterThan(forwardX));
          expect(backX, lessThan(forwardX));
          expect(find.text('PAUSADO'), findsNothing);
          final dockTop = tester.getRect(dock).top;
          final sidebar = width >= 1120
              ? find.byType(PulseDesktopLibrarySidebar)
              : find.byType(PulseExpandedSidebar);
          expect(tester.getRect(sidebar).bottom, closeTo(dockTop, 1));
          if (find.byType(PulseNowPlayingPanel).evaluate().isNotEmpty) {
            expect(tester.getRect(find.byType(PulseNowPlayingPanel)).bottom,
                closeTo(dockTop, 1));
          }
          expect(find.byTooltip('Configurações'), findsOneWidget);
          expect(find.byTooltip('Aleatório desativado'), findsOneWidget);
          expect(find.byTooltip('Repetir desativado'), findsOneWidget);
          expect(tester.getSize(dock).height, 88);
          final dockSurface = tester.widget<Container>(
            find.byKey(const Key('pulse-player-dock-surface')),
          );
          expect(
              dockSurface.color,
              appearance == PulseAppearance.light
                  ? pulseLightDockSurface
                  : pulseDockSurface);
          final artwork = find.descendant(
              of: dock, matching: find.byType(PulseTrackArtwork));
          expect(tester.getSize(artwork).width, 56);
          expect(tester.getRect(artwork).center.dy - tester.getRect(dock).top,
              closeTo(44, 1));
          final queue = find.descendant(
              of: dock, matching: find.byTooltip('Fila de reprodução'));
          expect(tester.getRect(queue).center.dy - tester.getRect(dock).top,
              closeTo(44, 1));
          final labels = [
            'Aleatório desativado',
            'Anterior',
            'Reproduzir',
            'Próxima',
            'Repetir desativado',
          ];
          final centers = labels
              .map((label) => tester
                  .getRect(
                    find.descendant(of: dock, matching: find.byTooltip(label)),
                  )
                  .center
                  .dx)
              .toList();
          expect(centers, orderedEquals(centers.toList()..sort()));
          for (final label in labels) {
            final control =
                find.descendant(of: dock, matching: find.byTooltip(label));
            expect(tester.getRect(control).center.dy - dockTop, closeTo(33, 1));
            final progress =
                find.descendant(of: dock, matching: find.byType(Slider));
            expect(tester.getRect(control).bottom,
                lessThan(tester.getRect(progress.first).center.dy - 10),
                reason: '$label must not collide with progress');
          }
          expect(
              find.descendant(
                  of: dock,
                  matching: find.byTooltip('Adicionar aos Favoritos')),
              findsOneWidget);
          expect(
            tester.getSize(find.byType(Slider).first).width,
            lessThanOrEqualTo(680),
          );
        } else {
          expect(find.byType(CompactMiniPlayer), findsOneWidget);
          expect(find.byType(Slider), findsOneWidget);
          expect(find.text('01:00'), findsOneWidget);
          expect(find.text('03:00'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          'goldens/pulse_controls_layout_${width}_${appearance.name}.png',
        );
      }
    }
  });

  testWidgets('desktop dock disables modes and hides timeline without a track',
      (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    final library = _ReviewLibraryController();
    final playback = _ReviewPlaybackController();
    addTearDown(library.dispose);
    addTearDown(playback.dispose);

    await _pumpPulsePage(
      tester,
      width: 1280,
      library: library,
      playback: playback,
    );

    expect(find.byType(PulsePlayerDock), findsOneWidget);
    expect(tester.getSize(find.byType(PulsePlayerDock)).height, 88);
    expect(find.byTooltip('Aleatório desativado'), findsOneWidget);
    expect(find.byTooltip('Repetir desativado'), findsOneWidget);
    expect(find.byTooltip('Selecione uma faixa para adicionar aos Favoritos'),
        findsOneWidget);
    final modeButtons = tester.widgetList<IconButton>(
      find.descendant(
        of: find.byType(PulsePlaybackModeButtons),
        matching: find.byType(IconButton),
      ),
    );
    expect(modeButtons, hasLength(4));
    expect(modeButtons.every((button) => button.onPressed == null), isTrue);
    expect(find.byType(Slider), findsOneWidget); // Volume remains available.
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeat queue and track states are captured in both themes', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    const track = AudioTrack(
      id: 'repeat-state-track',
      path: r'C:\Review fixtures\Music\repeat-state.mp3',
      title: 'Estado de repetição',
      artist: 'Pulse Review',
      album: 'Capturas',
      sizeBytes: 1000,
      modifiedAtMillis: 1,
    );

    for (final appearance in PulseAppearance.values) {
      for (final placement in ['dock', 'now_playing']) {
        final library = _ReviewLibraryController(
          snapshot: const LibrarySnapshot(
            rootPath: r'C:\Review fixtures\Music',
            tracks: [track],
          ),
        );
        final playback = _ReviewPlaybackController(
          track: track,
          isPlaying: true,
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 3),
        );
        addTearDown(library.dispose);
        addTearDown(playback.dispose);

        final width = placement == 'dock' ? 1280 : 360;
        await _pumpPulsePage(
          tester,
          width: width,
          library: library,
          playback: playback,
          appearance: appearance,
        );
        if (placement == 'now_playing') {
          await tester.tap(find.byTooltip('Mostrar a tela Tocando agora'));
          await tester.pumpAndSettle();
        }

        expect(find.byTooltip('Repetir desativado'), findsOneWidget);
        await tester.tap(find.byTooltip('Repetir desativado'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Repetir fila'), findsOneWidget);
        final queueBadge = find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data == 'Fila' &&
              widget.style?.fontSize == 10,
        );
        if (placement == 'dock') {
          expect(queueBadge, findsOneWidget);
        }
        await _capture(
          tester,
          'goldens/pulse_repeat_${placement}_queue_${appearance.name}.png',
        );

        await tester.tap(find.byTooltip('Repetir fila'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Repetir faixa'), findsOneWidget);
        if (placement == 'dock') {
          expect(queueBadge, findsNothing);
        }
        expect(find.text('Faixa'), findsOneWidget);
        expect(find.byIcon(Icons.repeat_one_rounded), findsOneWidget);
        await _capture(
          tester,
          'goldens/pulse_repeat_${placement}_track_${appearance.name}.png',
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('library density changes row height and keeps 48dp controls', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    final tracks = [
      _embeddedArtworkTrack,
      AudioTrack(
          id: 'density-track-2',
          path: _embeddedArtworkTrack.path,
          title: 'Faixa Dois',
          sizeBytes: _embeddedArtworkTrack.sizeBytes,
          modifiedAtMillis: _embeddedArtworkTrack.modifiedAtMillis,
          artist: _embeddedArtworkTrack.artist,
          album: _embeddedArtworkTrack.album),
      AudioTrack(
          id: 'density-track-3',
          path: _embeddedArtworkTrack.path,
          title: 'Faixa Três',
          sizeBytes: _embeddedArtworkTrack.sizeBytes,
          modifiedAtMillis: _embeddedArtworkTrack.modifiedAtMillis,
          artist: _embeddedArtworkTrack.artist,
          album: _embeddedArtworkTrack.album),
    ];
    final library = _ReviewLibraryController(
      snapshot: LibrarySnapshot(rootPath: r'C:\Review\Music', tracks: tracks),
      sourceState: LibrarySourceState.available,
    );
    final playback = _ReviewPlaybackController();
    addTearDown(library.dispose);
    addTearDown(playback.dispose);

    for (final density in PulseDensity.values) {
      for (final width in [360, 1280]) {
        await _pumpPulsePage(tester,
            width: width,
            library: library,
            playback: playback,
            density: density);
        final row = find.byType(PulseTrackRow).first;
        final expectedHeight = switch (density) {
          PulseDensity.compact => 56.0,
          PulseDensity.standard => 64.0,
          PulseDensity.comfortable => 72.0,
        };
        expect(tester.getSize(row).height, expectedHeight);
        expect(
          tester
              .getSize(find
                  .ancestor(
                    of: find.byTooltip('Adicionar aos favoritos'),
                    matching: find.byType(InkWell),
                  )
                  .first)
              .shortestSide,
          greaterThanOrEqualTo(48),
        );
        for (final tooltip in ['Adicionar aos favoritos', 'Mais opções']) {
          expect(
            tester.getSize(find.byTooltip(tooltip).first).shortestSide,
            greaterThanOrEqualTo(48),
            reason: tooltip,
          );
        }
        await _capture(tester,
            'goldens/pulse_library_density_${density.name}_${width}x800.png');
      }
    }
  });

  testWidgets(
    'PulseHomePage uses the correct navigation and player at each breakpoint',
    (tester) async {
      await _prepareReviewTest(tester);
      expect(buildPulseTheme().colorScheme.secondary, pulseAccent);
      expect(buildPulseTheme().colorScheme.secondaryContainer,
          pulseSelectedSurface);
      final library = _ReviewLibraryController();
      final playback = _ReviewPlaybackController();
      addTearDown(library.dispose);
      addTearDown(playback.dispose);

      const reviewCases = <({int width, String golden})>[
        (width: 360, golden: 'goldens/pulse_home_360x800.png'),
        (width: 599, golden: 'goldens/pulse_home_599x800.png'),
        (width: 600, golden: 'goldens/pulse_home_600x800.png'),
        (width: 719, golden: 'goldens/pulse_home_719x800.png'),
        (width: 720, golden: 'goldens/pulse_home_720x800.png'),
        (width: 839, golden: 'goldens/pulse_home_839x800.png'),
        (width: 840, golden: 'goldens/pulse_home_840x800.png'),
        (width: 1119, golden: 'goldens/pulse_home_1119x800.png'),
        (width: 1120, golden: 'goldens/pulse_home_1120x800.png'),
        (width: 1280, golden: 'goldens/pulse_home_1280x800.png'),
        (width: 1920, golden: 'goldens/pulse_home_1920x800.png'),
      ];

      for (final reviewCase in reviewCases) {
        await _pumpPulsePage(
          tester,
          width: reviewCase.width,
          library: library,
          playback: playback,
        );

        if (reviewCase.width < 600) {
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(find.byType(NavigationRail), findsNothing);
          expect(find.byType(CompactMiniPlayer), findsOneWidget);
          expect(find.text('SUA MÚSICA'), findsNothing);
          expect(find.text('PLAYER PRONTO'), findsNothing);
          expect(find.text('Escolha uma faixa'), findsOneWidget);
        } else if (reviewCase.width < 840) {
          expect(find.byType(NavigationBar), findsNothing);
          expect(find.byType(NavigationRail), findsOneWidget);
          expect(
            tester
                .widget<NavigationRail>(find.byType(NavigationRail))
                .labelType,
            NavigationRailLabelType.none,
          );
          expect(find.byTooltip('Biblioteca'), findsAtLeastNWidgets(1));
          expect(find.byType(CompactMiniPlayer), findsOneWidget);
          expect(find.text('SUA MÚSICA'), findsNothing);
          expect(find.text('PLAYER PRONTO'), findsNothing);
        } else {
          expect(find.byType(NavigationBar), findsNothing);
          expect(find.byType(NavigationRail), findsNothing);
          expect(find.byType(CompactMiniPlayer), findsNothing);
          expect(
              find.text(reviewCase.width >= 1120
                  ? 'Sua biblioteca'
                  : 'SUA BIBLIOTECA'),
              findsOneWidget);
          expect(
              find.text('Nenhuma faixa selecionada'), findsAtLeastNWidgets(1));
          expect(find.text('00:00'), findsNothing);
          expect(find.byTooltip('Adicionar pasta'), findsOneWidget);
        }
        expect(
          find.byType(PulseNowPlayingPanel),
          reviewCase.width >= 1120 ? findsOneWidget : findsNothing,
        );

        await _capture(tester, reviewCase.golden);
      }
    },
  );

  testWidgets(
    'single global search focuses from the sidebar and player panel respects its fit threshold',
    (tester) async {
      await _prepareReviewTest(tester);
      final library = _ReviewLibraryController();
      final playback = _ReviewPlaybackController();
      addTearDown(library.dispose);
      addTearDown(playback.dispose);

      await _pumpPulsePage(
        tester,
        width: 840,
        library: library,
        playback: playback,
      );
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.byTooltip('Focar busca da biblioteca'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byType(TextField).first)
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(find.byType(PulseNowPlayingPanel), findsNothing);

      await _pumpPulsePage(
        tester,
        width: 1119,
        library: library,
        playback: playback,
      );
      expect(find.byType(PulseNowPlayingPanel), findsNothing);

      await _pumpPulsePage(
        tester,
        width: 1120,
        library: library,
        playback: playback,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(PulseNowPlayingPanel), findsOneWidget);
      Focus.of(tester.element(find.byKey(const ValueKey('now-playing-header'))))
          .requestFocus();
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PulseNowPlayingPanel),
          matching: find.byTooltip('Entrar na tela cheia'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PulseExpandedPlayerView), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PulseExpandedPlayerView), findsNothing);
      expect(find.byType(PulseHomePage), findsOneWidget);
    },
  );

  testWidgets(
    'dense synthetic library truncates long metadata on compact and desktop',
    (tester) async {
      await _prepareReviewTest(tester);
      final tracks = _denseReviewTracks();
      final library = _ReviewLibraryController(
        snapshot: LibrarySnapshot(
          rootPath: r'C:\Review fixtures\Music',
          tracks: tracks,
          favoriteIds: {tracks.first.id},
          playlists: const [
            PulsePlaylist(
              id: 'fixture-playlist',
              name: 'Playlist longa para revisão visual',
              trackIds: ['fixture-track-00'],
            ),
          ],
        ),
      );
      final playback = _ReviewPlaybackController();
      addTearDown(library.dispose);
      addTearDown(playback.dispose);

      const longTitle =
          'A very long synthetic track title that must be truncated cleanly in the dense library';
      for (final width in [360, 1280]) {
        await _pumpPulsePage(
          tester,
          width: width,
          library: library,
          playback: playback,
        );
        if (width == 1280) {
          await tester.tap(find.descendant(
            of: find.byType(PulseDesktopLibrarySidebar),
            matching: find.text('Faixas'),
          ));
        } else {
          await tester.tap(find.text('Faixas').first);
        }
        await tester.pumpAndSettle();

        final title = tester.widget<Text>(find.descendant(
          of: find.byType(PulseTrackRow).first,
          matching: find.text(longTitle),
        ));
        expect(title.maxLines, 1);
        expect(title.overflow, TextOverflow.ellipsis);
        expect(find.byTooltip('Mais opções'), findsAtLeastNWidgets(4));
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          width == 360
              ? 'goldens/pulse_library_dense_360x800.png'
              : 'goldens/pulse_library_dense_1280x800.png',
        );
      }
    },
  );

  testWidgets(
    'collection shortcuts fit compact; album detail filters by album and artist',
    (tester) async {
      await _prepareReviewTest(tester);
      const tracks = [
        AudioTrack(
          id: 'north-track',
          path: r'C:\Review fixtures\Music\north.mp3',
          title: 'Faixa do Norte',
          artist: 'Artista Norte',
          album: 'Álbum compartilhado',
          sizeBytes: 2_000_000,
          modifiedAtMillis: 1_790_000_000_000,
        ),
        AudioTrack(
          id: 'south-track',
          path: r'C:\Review fixtures\Music\south.mp3',
          title: 'Faixa do Sul',
          artist: 'Artista Sul',
          album: 'Álbum compartilhado',
          sizeBytes: 2_100_000,
          modifiedAtMillis: 1_790_000_001_000,
        ),
      ];
      const longPlaylistName = 'Playlist longa para validar acessibilidade';
      final library = _ReviewLibraryController(
        snapshot: LibrarySnapshot(
          rootPath: r'C:\Review fixtures\Music',
          tracks: tracks,
          favoriteIds: {'north-track'},
          playlists: const [
            PulsePlaylist(
              id: 'long-playlist',
              name: longPlaylistName,
              trackIds: ['north-track'],
            ),
          ],
        ),
      );
      final playback = _ReviewPlaybackController(
        track: tracks.first,
        isPlaying: true,
        position: const Duration(seconds: 24),
        duration: const Duration(minutes: 2, seconds: 16),
      );
      addTearDown(library.dispose);
      addTearDown(playback.dispose);

      for (final width in [360, 1280]) {
        await _pumpPulsePage(
          tester,
          width: width,
          library: library,
          playback: playback,
        );
        expect(
          find.byType(PulseLibraryShortcut),
          findsNWidgets(width == 360 ? 4 : 2),
        );
        for (final shortcut in tester.widgetList<PulseLibraryShortcut>(
          find.byType(PulseLibraryShortcut),
        )) {
          final size = tester.getSize(find.byWidget(shortcut));
          expect(size.height, greaterThanOrEqualTo(48));
          if (width == 360) {
            expect(size.width, greaterThanOrEqualTo(48));
          }
        }
        expect(
          find.byTooltip(
            '$longPlaylistName · Playlist · 1 faixas',
          ),
          findsOneWidget,
        );

        if (width == 360) {
          expect(find.byType(ChoiceChip), findsNWidgets(3));
          await tester.tap(find.widgetWithText(ChoiceChip, 'Álbuns'));
        } else {
          await tester.tap(find.text('Álbuns').first);
        }
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ListTile, 'Álbum compartilhado'),
            findsNWidgets(2));
        await tester.tap(
          find.widgetWithText(ListTile, 'Álbum compartilhado').first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Artista Norte'), findsAtLeastNWidgets(1));
        expect(find.text('Faixa do Norte'), findsAtLeastNWidgets(1));
        expect(find.text('Artista Sul'), findsNothing);
        expect(find.text('Faixa do Sul'), findsNothing);
        expect(find.byTooltip('Reproduzir álbum'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          'goldens/pulse_album_open_${width}x800.png',
        );

        if (width == 1280) {
          await tester.tap(find.byTooltip('Voltar'));
          await tester.pumpAndSettle();
          expect(
            find.widgetWithText(ListTile, 'Álbum compartilhado'),
            findsNWidgets(2),
          );
          await tester.tap(find.byTooltip('Avançar'));
          await tester.pumpAndSettle();
          expect(find.text('Artista Norte'), findsAtLeastNWidgets(1));
        }

        await tester.tap(find.byTooltip('Voltar para Álbuns'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ListTile, 'Álbum compartilhado'),
            findsNWidgets(2));
      }
    },
  );

  testWidgets('desktop navigation history returns and advances safely', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    final tracks = _denseReviewTracks().take(4).toList(growable: false);
    final library = _ReviewLibraryController(
      snapshot: LibrarySnapshot(
        rootPath: r'C:\Review fixtures\Music',
        tracks: tracks,
        favoriteIds: {tracks.first.id},
        playlists: const [],
      ),
    );
    final playback = _ReviewPlaybackController();
    addTearDown(library.dispose);
    addTearDown(playback.dispose);

    await _pumpPulsePage(
      tester,
      width: 1280,
      library: library,
      playback: playback,
    );
    expect(find.byTooltip('Voltar'), findsOneWidget);
    expect(find.byTooltip('Avançar'), findsOneWidget);
    final backButton = find.ancestor(
      of: find.byTooltip('Voltar'),
      matching: find.byType(IconButton),
    );
    final forwardButton = find.ancestor(
      of: find.byTooltip('Avançar'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(backButton).onPressed, isNull);
    await tester.tap(find.text('Músicas curtidas').first);
    await tester.pumpAndSettle();
    expect(find.text('Ainda sem favoritos'), findsNothing);
    expect(tester.widget<IconButton>(backButton).onPressed, isNotNull);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.text('Acesso rápido'), findsOneWidget);
    expect(tester.widget<IconButton>(forwardButton).onPressed, isNotNull);

    await tester.tap(find.byTooltip('Avançar'));
    await tester.pumpAndSettle();
    expect(find.text('Ainda sem favoritos'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search with no matches is clear on compact and desktop', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    final library = _ReviewLibraryController(
      snapshot: LibrarySnapshot(tracks: _denseReviewTracks()),
    );
    final playback = _ReviewPlaybackController();
    addTearDown(library.dispose);
    addTearDown(playback.dispose);

    const query = 'no-match-review-927';
    for (final width in [360, 1280]) {
      await _pumpPulsePage(
        tester,
        width: width,
        library: library,
        playback: playback,
      );
      if (width == 1280) {
        await tester.tap(find.descendant(
          of: find.byType(PulseDesktopLibrarySidebar),
          matching: find.text('Faixas'),
        ));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();

      expect(find.text('Nenhum resultado para “$query”'), findsOneWidget);
      expect(find.text('Limpar busca'), findsOneWidget);
      expect(find.byTooltip('Limpar busca'), findsOneWidget);
      final clearAction = find.widgetWithText(FilledButton, 'Limpar busca');
      expect(
        find.descendant(
          of: clearAction,
          matching: find.byIcon(Icons.search_off_rounded),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _capture(
        tester,
        width == 360
            ? 'goldens/pulse_search_no_results_360x800.png'
            : 'goldens/pulse_search_no_results_1280x800.png',
      );
      await tester.tap(clearAction);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.textContaining('Nenhum resultado para'), findsNothing);
    }
  });

  testWidgets('active playback and Now Playing use synthetic track data', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    const track = AudioTrack(
      id: 'fixture-active-track',
      path: r'C:\Review fixtures\Music\luz-da-manha.mp3',
      title: 'Luz da manhã',
      artist: 'Maré Alta',
      album: 'Caminhos',
      sizeBytes: 3_400_000,
      modifiedAtMillis: 1_790_000_000_000,
    );
    final tracks = [track, ..._denseReviewTracks().take(7)];
    final library = _ReviewLibraryController(
      snapshot: LibrarySnapshot(
        rootPath: r'C:\Review fixtures\Music',
        tracks: tracks,
        favoriteIds: {track.id},
        playlists: [
          PulsePlaylist(
            id: 'active-review-playlist',
            name: 'Sessão de revisão',
            trackIds: tracks.take(3).map((item) => item.id).toList(),
          ),
        ],
      ),
    );
    final playback = _ReviewPlaybackController(
      track: track,
      isPlaying: true,
      position: const Duration(minutes: 1, seconds: 12),
      duration: const Duration(minutes: 4, seconds: 35),
    );
    addTearDown(library.dispose);
    addTearDown(playback.dispose);

    await _pumpPulsePage(
      tester,
      width: 360,
      library: library,
      playback: playback,
    );
    expect(find.byTooltip('Pausar'), findsOneWidget);
    final firstTrackRow = tester.getRect(find.byType(PulseTrackRow).first);
    final compactPlayer = tester.getRect(find.byType(CompactMiniPlayer));
    await _capture(tester, 'goldens/pulse_player_active_360x800.png');
    if (firstTrackRow.bottom > compactPlayer.top) {
      await tester.ensureVisible(find.byType(PulseTrackRow).first);
      await tester.pumpAndSettle();
    }
    expect(
      tester.getRect(find.byType(PulseTrackRow).first).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(CompactMiniPlayer)).top),
    );

    await tester.ensureVisible(find.text('Sessão de revisão').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sessão de revisão').first);
    await tester.pumpAndSettle();
    expect(find.text(track.title), findsWidgets);
    expect(find.textContaining('3 faixas'), findsWidgets);
    expect(find.byTooltip('Voltar para playlists'), findsOneWidget);
    await _capture(tester, 'goldens/pulse_playlist_active_360x800.png');

    await tester.tap(find.byTooltip('Mostrar a tela Tocando agora'));
    await tester.pumpAndSettle();
    expect(find.text('Tocando agora'), findsOneWidget);
    expect(find.text(track.title), findsWidgets);
    expect(find.byTooltip('Fila de reprodução'), findsOneWidget);
    expect(find.byType(PulsePlaybackModeButtons), findsOneWidget);
    expect(find.byTooltip('Aleatório desativado'), findsOneWidget);
    expect(find.byTooltip('Repetir desativado'), findsOneWidget);
    await tester.tap(find.byTooltip('Aleatório desativado'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Aleatório ativado'), findsOneWidget);
    await tester.tap(find.byTooltip('Repetir desativado'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Repetir fila'), findsOneWidget);
    await tester.tap(find.byTooltip('Repetir fila'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Repetir faixa'), findsOneWidget);
    await tester.tap(find.byTooltip('Repetir faixa'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Repetir desativado'), findsOneWidget);
    await tester.tap(find.byTooltip('Aleatório ativado'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Aleatório desativado'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'goldens/pulse_now_playing_360x800.png');

    await _pumpPulsePage(
      tester,
      width: 1280,
      library: library,
      playback: playback,
    );
    expect(find.byTooltip('Pausar'), findsOneWidget);
    expect(find.text(track.title), findsWidgets);
    expect(find.text(track.title), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(PulseHeader),
        matching: find.byTooltip('Configurações'),
      ),
      findsOneWidget,
    );
    expect(find.text('Configurações'), findsNothing);
    final dock = find.byType(PulsePlayerDock);
    final dockCenter = tester.getRect(dock).center.dx;
    final transportCenter = (tester.getCenter(find.byTooltip('Anterior')).dx +
            tester.getCenter(find.byTooltip('Próxima')).dx) /
        2;
    expect(
      (transportCenter - dockCenter).abs(),
      lessThanOrEqualTo(4),
      reason: 'transport=$transportCenter dock=$dockCenter',
    );
    expect(tester.getSize(find.byType(Slider).first).width,
        lessThanOrEqualTo(680));
    expect(find.byTooltip('Aleatório desativado'), findsOneWidget);
    expect(find.byTooltip('Repetir desativado'), findsOneWidget);
    await _capture(tester, 'goldens/pulse_player_active_1280x800.png');

    await tester.tap(find.text('Sessão de revisão').first);
    await tester.pumpAndSettle();
    expect(find.text(track.title), findsWidgets);
    expect(find.textContaining('3 faixas'), findsWidgets);
    await _capture(tester, 'goldens/pulse_playlist_active_1280x800.png');

    final pausedPlayback = _ReviewPlaybackController(track: track);
    addTearDown(pausedPlayback.dispose);
    await _pumpPulsePage(
      tester,
      width: 1280,
      library: library,
      playback: pausedPlayback,
    );
    expect(find.text('PAUSADO'), findsNothing);
    await _capture(tester, 'goldens/pulse_player_paused_1280x800.png');
  });

  testWidgets('library error remains visible without covering the player', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    const message = 'A pasta de revisão está desconectada.';
    final library = _ReviewLibraryController(errorMessage: message);
    final playback = _ReviewPlaybackController();
    addTearDown(library.dispose);
    addTearDown(playback.dispose);

    await _pumpPulsePage(
      tester,
      width: 1280,
      library: library,
      playback: playback,
    );
    expect(find.text(message), findsOneWidget);
    expect(find.text('Nenhuma faixa selecionada'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
    await _capture(tester, 'goldens/pulse_library_error_1280x800.png');
  });

  testWidgets('catalog recovery and blocked state fit compact and desktop', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    for (final width in [360, 1280]) {
      final library = _ReviewLibraryController(
        catalogRecoveryRequired: true,
        errorMessage:
            'O catálogo não foi alterado. Verifique os arquivos antes de criar uma biblioteca nova.',
      );
      final playback = _ReviewPlaybackController();
      addTearDown(library.dispose);
      addTearDown(playback.dispose);
      await _pumpPulsePage(
        tester,
        width: width,
        library: library,
        playback: playback,
      );
      expect(
          find.text('Não foi possível abrir o catálogo local'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(find.text('Ver arquivos de recuperação'), findsOneWidget);
      expect(find.byTooltip('Adicionar pasta'), findsNothing);
      expect(find.byTooltip('Escolher outra pasta'), findsNothing);
      expect(find.byTooltip('Nova playlist'), findsNothing);
      expect(find.byType(PulseHomePage), findsOneWidget);
      await _capture(
        tester,
        'goldens/pulse_catalog_recovery_blocked_${width}x800.png',
      );

      final recoveredLibrary = _ReviewLibraryController(
        snapshot: (() {
          final track = _denseReviewTracks().first;
          return LibrarySnapshot(
            rootPath: r'C:\Synthetic Music',
            tracks: [track],
            favoriteIds: {track.id},
            playlists: [
              PulsePlaylist(
                id: 'recovered-review-playlist',
                name: 'Lista recuperada',
                trackIds: [track.id],
              ),
            ],
            scannedAtMillis: 1791479000000,
          );
        })(),
        noticeMessage: 'O Pulse abriu a última cópia válida.',
        recoveredFromBackup: true,
        primaryCatalogPath: r'C:\Pulse\library.json',
        recoveryBackupPath: r'C:\Pulse\library.json.bak',
      );
      addTearDown(recoveredLibrary.dispose);
      await _pumpPulsePage(
        tester,
        width: width,
        library: recoveredLibrary,
        playback: playback,
      );
      expect(find.text('Catálogo recuperado'), findsOneWidget);
      expect(find.text('Ver detalhes'), findsOneWidget);
      await _capture(
        tester,
        'goldens/pulse_catalog_recovered_${width}x800.png',
      );
    }
  });

  testWidgets('source recovery states stay clear on compact and desktop', (
    tester,
  ) async {
    await _prepareReviewTest(tester);
    final tracks = _denseReviewTracks().take(3).toList(growable: false);
    const reviewRoot = r'C:\Review fixtures\Music';
    final playback = _ReviewPlaybackController(
      track: tracks.first,
      isPlaying: true,
    );
    addTearDown(playback.dispose);

    final cases = <({
      String name,
      LibrarySourceState state,
      bool scanning,
      String? scanAttemptPath,
      String? notice,
      String? error,
      String goldenPrefix,
    })>[
      (
        name: 'Pasta desconectada',
        state: LibrarySourceState.disconnected,
        scanning: false,
        scanAttemptPath: null,
        notice: null,
        error: null,
        goldenPrefix: 'pulse_source_disconnected',
      ),
      (
        name: 'Pasta desconectada',
        state: LibrarySourceState.disconnected,
        scanning: false,
        scanAttemptPath: r'C:\Review fixtures\Nova biblioteca',
        notice: null,
        error:
            'A pasta escolhida “Nova biblioteca” teve leitura parcial. A fonte e o catálogo atuais foram mantidos.',
        goldenPrefix: 'pulse_source_new_folder_partial',
      ),
      (
        name: 'Reconectando pasta',
        state: LibrarySourceState.disconnected,
        scanning: true,
        scanAttemptPath: reviewRoot,
        notice: null,
        error: null,
        goldenPrefix: 'pulse_source_reconnecting',
      ),
      (
        name: 'Lendo nova pasta',
        state: LibrarySourceState.disconnected,
        scanning: true,
        scanAttemptPath: r'C:\Review fixtures\Nova biblioteca',
        notice: null,
        error: null,
        goldenPrefix: 'pulse_source_new_folder_reading',
      ),
      (
        name: 'Falha ao ler a pasta',
        state: LibrarySourceState.readError,
        scanning: false,
        scanAttemptPath: null,
        notice: null,
        error: null,
        goldenPrefix: 'pulse_source_read_error',
      ),
      (
        name: 'Leitura incompleta',
        state: LibrarySourceState.partial,
        scanning: false,
        scanAttemptPath: null,
        notice: null,
        error: null,
        goldenPrefix: 'pulse_source_partial',
      ),
      (
        name: 'Pasta reconectada. Biblioteca atualizada.',
        state: LibrarySourceState.available,
        scanning: false,
        scanAttemptPath: null,
        notice: 'Pasta reconectada. Biblioteca atualizada.',
        error: null,
        goldenPrefix: 'pulse_source_reconnected',
      ),
      (
        name:
            'Nenhum arquivo MP3 foi encontrado. A biblioteca anterior foi preservada.',
        state: LibrarySourceState.available,
        scanning: false,
        scanAttemptPath: null,
        notice: null,
        error:
            'Nenhum arquivo MP3 foi encontrado. A biblioteca anterior foi preservada.',
        goldenPrefix: 'pulse_source_accessible_empty',
      ),
    ];

    for (final reviewCase in cases) {
      for (final width in [360, 1280]) {
        final library = _ReviewLibraryController(
          snapshot: LibrarySnapshot(
            rootPath: reviewRoot,
            tracks: tracks,
            favoriteIds: {tracks.first.id},
            playlists: const [
              PulsePlaylist(
                id: 'review-playlist',
                name: 'Playlist de revisão',
                trackIds: ['fixture-track-00'],
              ),
            ],
          ),
          sourceState: reviewCase.state,
          scanning: reviewCase.scanning,
          scanAttemptPath: reviewCase.scanAttemptPath,
          noticeMessage: reviewCase.notice,
          errorMessage: reviewCase.error,
        );
        addTearDown(library.dispose);
        await _pumpPulsePage(
          tester,
          width: width,
          library: library,
          playback: playback,
          settle: !reviewCase.scanning,
        );

        expect(find.text(reviewCase.name), findsOneWidget);
        if (reviewCase.state == LibrarySourceState.disconnected) {
          expect(
            find.textContaining(
              reviewCase.goldenPrefix == 'pulse_source_new_folder_reading'
                  ? 'catálogo atual'
                  : 'último catálogo',
            ),
            findsOneWidget,
          );
          if (reviewCase.goldenPrefix == 'pulse_source_new_folder_partial') {
            expect(find.textContaining('Nova biblioteca'), findsOneWidget);
          }
          if (reviewCase.goldenPrefix == 'pulse_source_new_folder_reading') {
            expect(
              find.textContaining('Nova biblioteca'),
              findsAtLeastNWidgets(2),
            );
            expect(find.textContaining('fonte salva “Music”'), findsOneWidget);
          }
        } else if (reviewCase.goldenPrefix == 'pulse_source_accessible_empty') {
          expect(find.text('Pasta desconectada'), findsNothing);
        } else if (reviewCase.state == LibrarySourceState.partial) {
          expect(
            find.textContaining('catálogo anterior foi mantido'),
            findsOneWidget,
          );
        } else if (reviewCase.state == LibrarySourceState.readError) {
          expect(
              find.textContaining('Confira o acesso à pasta'), findsOneWidget);
        }
        expect(find.byTooltip('Pausar'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          'goldens/${reviewCase.goldenPrefix}_${width}x800.png',
        );
      }
    }
  });

  testWidgets(
      'reconnect uses the saved folder; choosing another stays distinct',
      (tester) async {
    await _prepareReviewTest(tester);
    const root = r'C:\Review fixtures\Music';
    final library = _ReviewLibraryController(
      snapshot: const LibrarySnapshot(rootPath: root),
      sourceState: LibrarySourceState.disconnected,
    );
    final playback = _ReviewPlaybackController();
    addTearDown(library.dispose);
    addTearDown(playback.dispose);

    await _pumpPulsePage(
      tester,
      width: 360,
      library: library,
      playback: playback,
    );

    expect(find.text('Reconectar pasta'), findsOneWidget);
    expect(find.byTooltip('Escolher outra pasta'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Reconectar pasta'));
    await tester.pumpAndSettle();

    expect(library.folderRequests, [root]);
  });

  testWidgets('Jellyfin desktop catalog keeps its source and playlist view',
      (tester) async {
    await _prepareReviewTest(tester);
    final library = _ReviewLibraryController();
    final playback = _ReviewPlaybackController();
    final remote = _ReviewJellyfinController();
    addTearDown(library.dispose);
    addTearDown(playback.dispose);
    addTearDown(remote.dispose);
    for (final (width, height) in [(1280, 800), (1920, 1080)]) {
      await _pumpPulsePage(tester,
          width: width,
          height: height,
          library: library,
          playback: playback,
          jellyfin: remote);
      await tester.tap(find.text('Jellyfin').first);
      await tester.pumpAndSettle();
      expect(find.text('Faixa remota'), findsOneWidget);
      expect(find.text('Artista remoto • Jellyfin'), findsOneWidget);
      await _capture(
          tester, 'goldens/pulse_jellyfin_${width}x${height}_dark.png');
      await tester.tap(find.text('Playlist remota').first);
      await tester.pumpAndSettle();
      expect(find.text('Faixa remota'), findsOneWidget);
    }
  });

  testWidgets('r18 desktop visual review at 1280 1440 and 1920',
      (tester) async {
    await _prepareReviewTest(tester);
    final tracks = [_embeddedArtworkTrack, ..._denseReviewTracks().take(8)];
    final library = _ReviewLibraryController(
        snapshot: LibrarySnapshot(
      rootPath: r'C:\Review fixtures\Music',
      tracks: tracks,
      favoriteIds: {_embeddedArtworkTrack.id},
      playlists: const [
        PulsePlaylist(
          id: 'r18-mix',
          name: 'Mix local de revisão',
          trackIds: ['embedded-artwork-review-track'],
        )
      ],
    ));
    final playback = _ReviewPlaybackController(
      track: _embeddedArtworkTrack,
      isPlaying: true,
      position: const Duration(minutes: 1, seconds: 12),
      duration: const Duration(minutes: 3, seconds: 40),
    );
    addTearDown(library.dispose);
    addTearDown(playback.dispose);
    for (final (width, height) in [
      (1280, 800),
      (1440, 900),
      (1920, 1080),
    ]) {
      await _pumpPulsePage(tester,
          width: width,
          height: height,
          library: library,
          playback: playback,
          reviewKey: 'r18-library');
      expect(find.byType(PulseDesktopLibrarySidebar), findsOneWidget);
      await _capture(tester, 'goldens/r18_library_${width}x$height.png');
      await tester.tap(find.byType(PulseCollectionCard).first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reproduzir álbum'), findsOneWidget);
      await _capture(tester, 'goldens/r18_album_${width}x$height.png');

      await _pumpPulsePage(tester,
          width: width,
          height: height,
          library: library,
          playback: playback,
          reviewKey: 'r18-playlist');
      await tester.tap(find
          .descendant(
              of: find.byType(PulseDesktopLibrarySidebar),
              matching: find.text('Mix local de revisão'))
          .first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reproduzir playlist'), findsOneWidget);
      await _capture(tester, 'goldens/r18_playlist_${width}x$height.png');

      await _pumpPulsePage(tester,
          width: width,
          height: height,
          library: library,
          playback: playback,
          reviewKey: 'r18-now');
      await _capture(tester, 'goldens/r18_nowplaying_${width}x$height.png');
      await tester.tap(find
          .descendant(
              of: find.byType(PulsePlayerDock),
              matching: find.byTooltip('Fila de reprodução'))
          .first);
      await tester.pumpAndSettle();
      expect(find.byType(PulseQueuePanel), findsOneWidget);
      await _capture(tester, 'goldens/r18_queue_${width}x$height.png');

      await _pumpPulsePage(tester,
          width: width,
          height: height,
          library: library,
          playback: playback,
          reviewKey: 'r18-settings');
      await tester.tap(find.byTooltip('Configurações').first);
      await tester.pumpAndSettle();
      await _capture(tester, 'goldens/r18_settings_${width}x$height.png');
      await tester.tap(find.text('Jellyfin').last);
      await tester.pumpAndSettle();
      await _capture(
          tester, 'goldens/r18_settings_jellyfin_${width}x$height.png');
    }
  });
}

Future<void> _prepareReviewTest(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (!_reviewFontsLoaded) {
    await _loadReviewFonts();
    _reviewFontsLoaded = true;
  }
  _mockAudioPlayerPlatform();
}

Future<void> _pumpPulsePage(
  WidgetTester tester, {
  required int width,
  int height = 800,
  required _ReviewLibraryController library,
  required _ReviewPlaybackController playback,
  JellyfinController? jellyfin,
  PulseDensity density = PulseDensity.compact,
  PulseAppearance appearance = PulseAppearance.dark,
  PulsePalette palette = PulsePalette.navyGreen,
  bool settle = true,
  String? reviewKey,
}) async {
  tester.view.physicalSize = Size(width.toDouble(), height.toDouble());
  await tester.pumpWidget(
    _reviewApp(
      key: ValueKey('review-$width-$height-${reviewKey ?? ''}'),
      library: library,
      playback: playback,
      jellyfin: jellyfin,
      density: density,
      appearance: appearance,
      palette: palette,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.takeException(), isNull, reason: 'Layout failed at $width dp');
  expect(find.byType(PulseHomePage), findsOneWidget);
}

Future<void> _capture(WidgetTester tester, String golden) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(golden));
}

Future<void> _loadReviewFonts() async {
  final windowsFont = File(r'C:\Windows\Fonts\segoeui.ttf');
  final materialIcons = File(
    'tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  final textFontLoader = FontLoader('PulseReview')
    ..addFont(
      Future.value(ByteData.sublistView(windowsFont.readAsBytesSync())),
    );
  await textFontLoader.load();

  final iconFontLoader = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(ByteData.sublistView(materialIcons.readAsBytesSync())),
    );
  await iconFontLoader.load();
}

void _mockAudioPlayerPlatform() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const globalMethodChannel = MethodChannel('xyz.luan/audioplayers.global');
  const globalEventChannel = EventChannel(
    'xyz.luan/audioplayers.global/events',
  );
  const playerMethodChannel = MethodChannel('xyz.luan/audioplayers');

  messenger.setMockMethodCallHandler(
    globalMethodChannel,
    (call) async => null,
  );
  messenger.setMockStreamHandler(
    globalEventChannel,
    MockStreamHandler.inline(onListen: (arguments, events) {}),
  );
  messenger.setMockMethodCallHandler(playerMethodChannel, (call) async {
    if (call.method == 'create') {
      final arguments = call.arguments! as Map<Object?, Object?>;
      final playerId = arguments['playerId']! as String;
      messenger.setMockStreamHandler(
        EventChannel('xyz.luan/audioplayers/events/$playerId'),
        MockStreamHandler.inline(onListen: (arguments, events) {}),
      );
    }
    return null;
  });
}

List<AudioTrack> _denseReviewTracks() => List<AudioTrack>.generate(
      32,
      (index) => AudioTrack(
        id: 'fixture-track-${index.toString().padLeft(2, '0')}',
        path: 'C:\\Review fixtures\\Music\\track-$index.mp3',
        title: index == 0
            ? 'A very long synthetic track title that must be truncated cleanly in the dense library'
            : 'Synthetic track ${index + 1}: The quiet afternoon session',
        artist: index == 0
            ? 'An exceptionally long artist credit for checking subtitle truncation'
            : 'Pulse Review Ensemble ${index % 5 + 1}',
        album: index == 0
            ? 'A deliberately long album title that exercises available row width'
            : 'Offline collection ${index % 4 + 1}',
        sizeBytes: 2_400_000 + index * 1000,
        modifiedAtMillis: 1_790_000_000_000 + index * 1000,
      ),
      growable: false,
    );

Future<Uint8List> _embeddedPngMp3() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 320, 180),
    ui.Paint()..color = const ui.Color(0xFF343A78),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 96, 180),
    ui.Paint()..color = const ui.Color(0xFF288F83),
  );
  canvas.drawCircle(
    const ui.Offset(160, 90),
    62,
    ui.Paint()..color = const ui.Color(0xFFE8894A),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(220, 0, 100, 180),
    ui.Paint()..color = const ui.Color(0xFFB84D69),
  );
  final image = await recorder.endRecording().toImage(320, 180);
  late final Uint8List png;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }

  final picture = <int>[
    0,
    ...ascii.encode('image/png'),
    0,
    3,
    0,
    ...png,
  ];
  final frame = <int>[
    ...ascii.encode('APIC'),
    ..._syncSafeArtworkSize(picture.length),
    0,
    0,
    ...picture,
  ];
  return Uint8List.fromList([
    ...ascii.encode('ID3'),
    4,
    0,
    0,
    ..._syncSafeArtworkSize(frame.length),
    ...frame,
  ]);
}

List<int> _syncSafeArtworkSize(int value) => [
      (value >> 21) & 0x7F,
      (value >> 14) & 0x7F,
      (value >> 7) & 0x7F,
      value & 0x7F,
    ];

class _ReviewLibraryController extends LibraryController {
  _ReviewLibraryController({
    LibrarySnapshot snapshot = const LibrarySnapshot(),
    this.sourceState = LibrarySourceState.notConfigured,
    this.scanning = false,
    this.scanAttemptPath,
    this.noticeMessage,
    this.errorMessage,
    this.catalogRecoveryRequired = false,
    this.recoveredFromBackup = false,
    this.primaryCatalogPath,
    this.recoveryBackupPath,
  })  : _snapshot = snapshot,
        super(WindowsLibraryStore());

  final LibrarySnapshot _snapshot;

  @override
  LibrarySnapshot get snapshot => _snapshot;

  @override
  bool get loading => false;

  @override
  final bool scanning;

  @override
  final String? scanAttemptPath;

  @override
  final LibrarySourceState sourceState;

  @override
  final String? noticeMessage;

  @override
  final String? errorMessage;

  @override
  final bool catalogRecoveryRequired;

  @override
  final bool recoveredFromBackup;

  @override
  final String? primaryCatalogPath;

  @override
  final String? recoveryBackupPath;

  final folderRequests = <String>[];

  @override
  Future<void> addFolder(String rootPath) async {
    folderRequests.add(rootPath);
  }
}

class _ReviewPlaybackController extends PlaybackController {
  _ReviewPlaybackController({
    this.track,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  final AudioTrack? track;

  @override
  final bool isPlaying;

  @override
  final Duration position;

  @override
  final Duration duration;

  @override
  AudioTrack? get currentTrack => track;

  @override
  List<AudioTrack> get queue => track == null ? const [] : [track!];

  @override
  int get currentIndex => track == null ? -1 : 0;

  @override
  Future<void> togglePlayback() async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> skipPrevious() async {}

  @override
  Future<void> seek(Duration value) async {}

  @override
  Future<void> playQueue(List<AudioTrack> tracks, int startIndex) async {}

  @override
  Future<void> playQueueItem(int index) async {}
}

Widget _reviewApp({
  required Key key,
  required _ReviewLibraryController library,
  required _ReviewPlaybackController playback,
  JellyfinController? jellyfin,
  PulseDensity density = PulseDensity.compact,
  PulseAppearance appearance = PulseAppearance.dark,
  PulsePalette palette = PulsePalette.navyGreen,
}) {
  var preferences = PulsePreferences(
      density: density, appearance: appearance, palette: palette);
  return MaterialApp(
    key: key,
    title: 'Pulse',
    debugShowCheckedModeBanner: false,
    theme: buildPulseTheme(fontFamily: 'PulseReview'),
    home: StatefulBuilder(
        builder: (context, setState) => Theme(
              data: buildPulseTheme(
                  fontFamily: 'PulseReview',
                  light: preferences.appearance == PulseAppearance.light,
                  palette: preferences.palette,
                  density: switch (preferences.density) {
                    PulseDensity.compact => VisualDensity.compact,
                    PulseDensity.standard => VisualDensity.standard,
                    PulseDensity.comfortable =>
                      const VisualDensity(horizontal: 1, vertical: 1),
                  }),
              child: PulseHomePage(
                  library: library,
                  jellyfin: jellyfin,
                  playback: playback,
                  preferences: preferences,
                  onPreferencesChanged: (next) async =>
                      setState(() => preferences = next)),
            )),
  );
}

class _ReviewJellyfinController extends JellyfinController {
  static const remoteTrack = AudioTrack(
    id: 'jellyfin:review-song',
    path: 'review-song',
    title: 'Faixa remota',
    artist: 'Artista remoto',
    album: 'Álbum remoto',
    sizeBytes: 0,
    modifiedAtMillis: 0,
    source: AudioSource.jellyfin,
  );

  @override
  bool get connected => true;

  @override
  List<AudioTrack> get tracks => const [remoteTrack];

  @override
  List<Map<String, dynamic>> get artists => const [
        {'Id': 'artist-1', 'Name': 'Artista remoto'}
      ];

  @override
  List<Map<String, dynamic>> get playlists => const [
        {'Id': 'playlist-1', 'Name': 'Playlist remota'}
      ];

  @override
  Future<List<AudioTrack>> playlistTracks(String playlistId) async =>
      const [remoteTrack];

  @override
  Future<void> refresh() async {}
}
