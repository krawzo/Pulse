import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app/pulse_theme.dart';
import 'pulse_navigation.dart';
import 'pulse_window_controls.dart';

class PulseHeader extends StatelessWidget {
  const PulseHeader({
    super.key,
    required this.destination,
    required this.compact,
    required this.hasLibrarySource,
    required this.showPrimaryAction,
    required this.queryController,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onAddFolder,
    required this.onCreatePlaylist,
    required this.onOpenSettings,
    this.onOpenAccount,
    this.accountName,
    this.accountImageUrl,
    required this.onExit,
    this.onHome,
    this.searchFocusNode,
    this.onOpenDrawer,
    this.onToggleNowPlayingPanel,
    this.onOpenNowPlaying,
    this.nowPlayingPanelOpen = false,
    this.showNowPlayingAction = false,
    this.showSettingsAction = false,
    this.showSettingsLeading = false,
    this.showSearch = true,
    this.showHistoryNavigation = false,
    this.showWindowControls = false,
    this.canGoBack = false,
    this.canGoForward = false,
    this.onGoBack,
    this.onGoForward,
  });

  final PulseDestination destination;
  final bool compact;
  final bool hasLibrarySource;
  final bool showPrimaryAction;
  final TextEditingController queryController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final VoidCallback onAddFolder;
  final VoidCallback onCreatePlaylist;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenAccount;
  final String? accountName;
  final String? accountImageUrl;
  final VoidCallback onExit;
  final VoidCallback? onHome;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onToggleNowPlayingPanel;
  final VoidCallback? onOpenNowPlaying;
  final bool nowPlayingPanelOpen;
  final bool showNowPlayingAction;
  final bool showSettingsAction;
  final bool showSettingsLeading;
  final bool showSearch;
  final bool showHistoryNavigation;
  final bool showWindowControls;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback? onGoBack;
  final VoidCallback? onGoForward;

  @override
  Widget build(BuildContext context) {
    final actions = _buildActions(context);
    final palette = PulsePaletteTheme.of(context);
    return Material(
      color: palette.dock,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 8 : 16, 6,
            showWindowControls ? 0 : (compact ? 12 : 16), 6),
        child: compact
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (onOpenDrawer case final openDrawer?)
                        IconButton(
                          tooltip: 'Abrir navegação',
                          onPressed: openDrawer,
                          icon: const Icon(Icons.menu_rounded),
                        ),
                      if (showWindowControls) _buildMoreMenu(),
                      if (!showWindowControls || onOpenDrawer == null)
                        const _PulseBrand(),
                      if (showWindowControls)
                        const Expanded(
                          child: DragToMoveArea(child: SizedBox(height: 52)),
                        )
                      else
                        const Spacer(),
                      if (!showWindowControls) ...actions,
                      if (showWindowControls && onOpenAccount != null)
                        _buildAccountButton(context),
                      if (showWindowControls)
                        const PulseWindowControls(compact: true),
                    ],
                  ),
                  if (showSearch) ...[
                    const SizedBox(height: 4),
                    _buildSearchField(context),
                  ],
                ],
              )
            : SizedBox(
                height: 52,
                child: Row(children: [
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width < 1100 ? 205 : 260,
                    child: Row(children: [
                      if (showWindowControls)
                        _buildMoreMenu()
                      else
                        const _PulseBrand(),
                      if (showHistoryNavigation) ...[
                        IconButton(
                          tooltip: 'Voltar',
                          onPressed: canGoBack ? onGoBack : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        IconButton(
                          tooltip: 'Avançar',
                          onPressed: canGoForward ? onGoForward : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                      if (showWindowControls)
                        const Expanded(
                          child: DragToMoveArea(child: SizedBox(height: 52)),
                        )
                      else
                        const Spacer(),
                    ]),
                  ),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (showWindowControls)
                          const DragToMoveArea(child: SizedBox.expand()),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 570),
                            child: Row(children: [
                              Tooltip(
                                message: 'Início',
                                child: Material(
                                  color: palette.raised,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: onHome,
                                    child: const SizedBox.square(
                                      dimension: 48,
                                      child: Icon(Icons.home_rounded, size: 26),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (showSearch)
                                Expanded(child: _buildSearchField(context)),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: showWindowControls
                        ? 152
                        : MediaQuery.sizeOf(context).width < 1100
                            ? 205
                            : 260,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: actions),
                  ),
                  if (showWindowControls) const PulseWindowControls(),
                ]),
              ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final result = <Widget>[];
    if (!compact && showSettingsLeading) {
      result.add(IconButton(
        tooltip: destination == PulseDestination.settings
            ? 'Voltar à biblioteca'
            : 'Configurações',
        onPressed: onOpenSettings,
        icon: const Icon(Icons.settings_outlined),
      ));
    }
    if (destination == PulseDestination.settings && !showSettingsLeading) {
      result.add(
        IconButton(
          tooltip: 'Voltar à biblioteca',
          onPressed: onOpenSettings,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      );
    } else if (showPrimaryAction) {
      if (compact || destination == PulseDestination.playlists) {
        result.add(
          IconButton.filledTonal(
            tooltip: destination == PulseDestination.playlists
                ? 'Nova playlist'
                : hasLibrarySource
                    ? 'Escolher outra pasta'
                    : 'Adicionar pasta',
            onPressed: destination == PulseDestination.playlists
                ? onCreatePlaylist
                : onAddFolder,
            icon: Icon(
              destination == PulseDestination.playlists
                  ? Icons.add_rounded
                  : Icons.create_new_folder_outlined,
            ),
          ),
        );
      } else {
        result.add(
          IconButton(
            tooltip: destination == PulseDestination.playlists
                ? 'Nova playlist'
                : hasLibrarySource
                    ? 'Escolher outra pasta'
                    : 'Adicionar pasta',
            onPressed: destination == PulseDestination.playlists
                ? onCreatePlaylist
                : onAddFolder,
            icon: Icon(
              destination == PulseDestination.playlists
                  ? Icons.add_rounded
                  : Icons.create_new_folder_outlined,
            ),
          ),
        );
      }
    }
    if (showSettingsAction && destination != PulseDestination.settings) {
      result.add(
        IconButton(
          tooltip: 'Configurações',
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
      );
    }
    if (showNowPlayingAction) {
      final togglesPanel = onToggleNowPlayingPanel != null;
      final actionLabel = togglesPanel && nowPlayingPanelOpen
          ? 'Ocultar a tela Tocando agora'
          : 'Mostrar a tela Tocando agora';
      result.add(
        IconButton(
          tooltip: actionLabel,
          onPressed: onToggleNowPlayingPanel ?? onOpenNowPlaying,
          icon: togglesPanel && nowPlayingPanelOpen
              ? const Icon(Icons.keyboard_double_arrow_right_rounded)
              : const Icon(Icons.keyboard_double_arrow_left_rounded),
        ),
      );
    }
    if (onOpenAccount != null) {
      result.add(_buildAccountButton(context));
    }
    if (!showWindowControls) result.add(_buildMoreMenu());
    return result;
  }

  Widget _buildAccountButton(BuildContext context) {
    final label = accountName?.trim();
    final accent = PulsePaletteTheme.of(context).accent;
    final onAccent = Theme.of(context).colorScheme.onPrimary;
    return IconButton(
      tooltip:
          label == null || label.isEmpty ? 'Entrar no Pulse' : 'Conta: $label',
      onPressed: onOpenAccount,
      icon: CircleAvatar(
        radius: 16,
        backgroundColor: accent,
        foregroundImage:
            accountImageUrl == null ? null : NetworkImage(accountImageUrl!),
        child: label == null || label.isEmpty
            ? Icon(Icons.person_rounded, size: 20, color: onAccent)
            : Text(label[0].toUpperCase(),
                style: TextStyle(color: onAccent, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _buildMoreMenu() => PopupMenuButton<String>(
        tooltip: 'Mais opções do Pulse',
        onSelected: (value) {
          switch (value) {
            case 'settings':
              onOpenSettings();
              return;
            case 'primary':
              destination == PulseDestination.playlists
                  ? onCreatePlaylist()
                  : onAddFolder();
              return;
            case 'nowPlaying':
              (onToggleNowPlayingPanel ?? onOpenNowPlaying)?.call();
              return;
            case 'exit':
              onExit();
              return;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'settings',
            child: Text(destination == PulseDestination.settings
                ? 'Voltar à biblioteca'
                : 'Configurações'),
          ),
          if (showPrimaryAction)
            PopupMenuItem(
              value: 'primary',
              child: Text(destination == PulseDestination.playlists
                  ? 'Nova playlist'
                  : hasLibrarySource
                      ? 'Escolher outra pasta'
                      : 'Adicionar pasta'),
            ),
          if (showNowPlayingAction)
            const PopupMenuItem(
              value: 'nowPlaying',
              child: Text('Tocando agora'),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'exit',
            child: Text('Sair do Pulse'),
          ),
        ],
        icon: const Icon(Icons.more_horiz_rounded),
      );

  Widget _buildSearchField(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final palette = PulsePaletteTheme.of(context);
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
    return SizedBox(
      height: 48,
      child: TextField(
        focusNode: searchFocusNode,
        controller: queryController,
        onChanged: onQueryChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'O que você quer ouvir?',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: queryController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpar busca',
                  onPressed: onClearQuery,
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: palette.raised,
          border: outline,
          enabledBorder: outline,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(
              color: light || palette.isFrosted
                  ? palette.accent
                  : (palette.isOriginal ? pulseAccent : pulseDarkText),
              width: 2,
            ),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
      ),
    );
  }
}

class _PulseBrand extends StatelessWidget {
  const _PulseBrand();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.graphic_eq_rounded,
            color: PulsePaletteTheme.of(context).emphasisInk,
            size: 27,
          ),
          const SizedBox(width: 8),
          Text(
            'Pulse',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      );
}
