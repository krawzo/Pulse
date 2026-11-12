import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/pulse_app_metadata.dart';
import '../app/pulse_theme.dart';
import '../domain/pulse_preferences.dart';
import '../state/library_controller.dart';
import '../state/jellyfin_controller.dart';
import '../data/navidrome_client.dart';
import '../data/jellyfin_client.dart';
import 'pulse_library_insights.dart';

enum _SettingsSection {
  library,
  jellyfin,
  playback,
  appearance,
  startup,
  storage,
  about
}

class PulseSettingsPage extends StatefulWidget {
  const PulseSettingsPage(
      {super.key,
      required this.preferences,
      required this.library,
      required this.jellyfin,
      required this.onPreferencesChanged,
      required this.onChooseFolder,
      required this.onRescan,
      required this.onExit,
      required this.onClearArtwork,
      this.desktop = false});

  final PulsePreferences preferences;
  final LibraryController library;
  final JellyfinController jellyfin;
  final Future<void> Function(PulsePreferences) onPreferencesChanged;
  final VoidCallback onChooseFolder;
  final VoidCallback onRescan;
  final VoidCallback onExit;
  final VoidCallback onClearArtwork;
  final bool desktop;

  @override
  State<PulseSettingsPage> createState() => _PulseSettingsPageState();
}

class _PulseSettingsPageState extends State<PulseSettingsPage> {
  late final TextEditingController _server =
      TextEditingController(text: widget.jellyfin.server);
  final _user = TextEditingController();
  final _password = TextEditingController();
  late MusicServerKind _serverKind = widget.jellyfin.serverKind;
  late Future<bool> _savedServerSession =
      widget.jellyfin.hasSavedSession(_serverKind);
  bool _connecting = false;
  String? _connectionMessage;
  _SettingsSection? _selected;
  PulsePalette? _hoveredPalette;
  PulsePalette? _focusedPalette;
  final Map<PulsePalette, FocusNode> _paletteFocusNodes = {
    for (final palette in PulsePalette.values)
      palette: FocusNode(debugLabel: 'Paleta ${palette.name}'),
  };

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _password.dispose();
    for (final node in _paletteFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.desktop) _selected = _SettingsSection.library;
  }

  @override
  Widget build(BuildContext context) {
    final names = _SettingsSection.values
        .where((section) =>
            !Platform.isAndroid || section != _SettingsSection.startup)
        .toList(growable: false);
    if (widget.desktop) {
      final density = widget.preferences.density;
      final minimumHeight = switch (density) {
        PulseDensity.compact => 56.0,
        PulseDensity.standard => 64.0,
        PulseDensity.comfortable => 72.0,
      };
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            children: [
              for (final section in names)
                _desktopSettingsSection(context, section, minimumHeight),
            ],
          ),
        ),
      );
    }
    return _selected == null
        ? ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
                for (final section in names)
                  _indexTile(context, section, false,
                      () => setState(() => _selected = section)),
              ])
        : _detail(context, _selected!);
  }

  Widget _indexTile(BuildContext context, _SettingsSection section,
      bool selected, VoidCallback onTap) {
    final (title, summary, icon) = _sectionInfo(section);
    if (widget.desktop) {
      return ListTile(
        selected: selected,
        minTileHeight: 52,
        minLeadingWidth: 24,
        horizontalTitleGap: 4,
        leading: Icon(icon),
        title: Text(title,
            maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 13)),
        onTap: onTap,
      );
    }
    return Card(
        color:
            selected ? Theme.of(context).colorScheme.secondaryContainer : null,
        child: ListTile(
            minVerticalPadding: 8,
            leading: Icon(icon),
            title: Text(title),
            subtitle:
                Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onTap));
  }

  Widget _detail(BuildContext context, _SettingsSection section) {
    final (title, _, icon) = _sectionInfo(section);
    final density = widget.preferences.density;
    final minimumHeight = switch (density) {
      PulseDensity.compact => 56.0,
      PulseDensity.standard => 64.0,
      PulseDensity.comfortable => 72.0,
    };
    final content = ListView(
        padding: EdgeInsets.fromLTRB(
            widget.desktop ? 20 : 16, 8, widget.desktop ? 20 : 16, 24),
        children: [
          if (!widget.desktop)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton.icon(
                    onPressed: () => setState(() => _selected = null),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Configurações'))),
          if (widget.desktop)
            Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                child: Text(title,
                    style: Theme.of(context).textTheme.headlineSmall)),
          _section(context, title, icon, _controls(section, minimumHeight)),
        ]);
    if (widget.desktop) {
      return Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: content));
    }
    return content;
  }

  Widget _desktopSettingsSection(
      BuildContext context, _SettingsSection section, double minimumHeight) {
    final (title, _, _) = _sectionInfo(section);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
            child: Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
          ),
          ..._controls(section, minimumHeight),
          const Divider(height: 20),
        ],
      ),
    );
  }

  List<Widget> _controls(_SettingsSection section, double minimumHeight) =>
      switch (section) {
        _SettingsSection.library => [
            SwitchListTile(
                minTileHeight: minimumHeight,
                title: const Text('Usar layout compacto da biblioteca'),
                subtitle: const Text(
                    'Mostra mais itens na lista lateral da biblioteca.'),
                value: widget.preferences.compactLibraryLayout,
                onChanged: (value) => _change(
                    widget.preferences.copyWith(compactLibraryLayout: value))),
            SwitchListTile(
                minTileHeight: minimumHeight,
                title: const Text('Mostrar arquivos locais'),
                subtitle: const Text(
                    'Exibe a coleção lida da pasta escolhida no Pulse.'),
                value: widget.preferences.showLocalFiles,
                onChanged: (value) => _change(
                    widget.preferences.copyWith(showLocalFiles: value))),
            ListTile(
                minTileHeight: minimumHeight,
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(Platform.isAndroid
                    ? 'Adicionar músicas locais'
                    : 'Pasta da biblioteca'),
                subtitle: Tooltip(
                    message: widget.library.snapshot.rootPath ??
                        (Platform.isAndroid
                            ? 'Nenhuma música importada'
                            : 'Nenhuma pasta selecionada'),
                    child: Text(
                        Platform.isAndroid
                            ? '${widget.library.snapshot.tracks.length} faixas locais no Pulse'
                            : widget.library.snapshot.rootPath ??
                                'Nenhuma pasta selecionada',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: widget.onChooseFolder),
            ListTile(
                minTileHeight: minimumHeight,
                leading: const Icon(Icons.sync_rounded),
                title: const Text('Reanalisar biblioteca'),
                subtitle: Text(widget.library.scanning
                    ? 'Analisando a pasta…'
                    : Platform.isAndroid
                        ? 'Atualiza a pasta selecionada ou relê os arquivos importados'
                        : 'Atualiza as faixas encontradas nesta pasta'),
                trailing: widget.library.scanning
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded),
                onTap: widget.library.snapshot.rootPath == null ||
                        widget.library.scanning
                    ? null
                    : widget.onRescan),
            _sourceState(context),
          ],
        _SettingsSection.jellyfin => _jellyfinControls(),
        _SettingsSection.playback => [
            SwitchListTile(
                minTileHeight: minimumHeight,
                title: const Text('Continuar de onde parei'),
                subtitle: const Text(
                    'Restaura a última faixa e posição. A reprodução só começa quando você tocar em Reproduzir.'),
                value: widget.preferences.continuePlayback,
                onChanged: (value) => _change(widget.preferences.copyWith(
                    continuePlayback: value, clearCheckpoint: !value))),
            SwitchListTile(
                minTileHeight: minimumHeight,
                title: const Text('Sem pausas'),
                subtitle: const Text(
                    'Avança automaticamente para a próxima faixa ao terminar.'),
                value: widget.preferences.autoPlayNext,
                onChanged: (value) =>
                    _change(widget.preferences.copyWith(autoPlayNext: value))),
            SwitchListTile(
                minTileHeight: minimumHeight,
                title: const Text('Fazer transição gradual de faixas'),
                subtitle: Text(
                    'Sobrepõe as faixas por ${widget.preferences.crossfadeSeconds} s.'),
                value: widget.preferences.crossfadeEnabled,
                onChanged: (value) => _change(
                    widget.preferences.copyWith(crossfadeEnabled: value))),
            ListTile(
              minTileHeight: minimumHeight,
              title: const Text('Duração da transição'),
              subtitle: Slider(
                value: widget.preferences.crossfadeSeconds.toDouble(),
                min: 0,
                max: 12,
                divisions: 12,
                label: '${widget.preferences.crossfadeSeconds} s',
                onChanged: widget.preferences.crossfadeEnabled
                    ? (value) => _change(widget.preferences
                        .copyWith(crossfadeSeconds: value.round()))
                    : null,
              ),
            ),
            SwitchListTile(
                minTileHeight: minimumHeight,
                title: const Text('Automix'),
                subtitle: const Text(
                    'Ainda não disponível: exige análise e receitas de transição para cada par de faixas.'),
                value: false,
                onChanged: null),
            SwitchListTile(
                minTileHeight: minimumHeight,
                title: const Text('Normalizar o volume'),
                subtitle: const Text(
                    'Usa ReplayGain quando a faixa tem esses metadados. Sem eles, mantém o volume original.'),
                value: widget.preferences.normalizeVolume,
                onChanged: (value) => _change(
                    widget.preferences.copyWith(normalizeVolume: value))),
            ListTile(
              minTileHeight: minimumHeight,
              title: const Text('Nível do volume'),
              subtitle: const Text('Ajusta o ganho das faixas com ReplayGain.'),
              trailing: DropdownButton<PulseVolumeLevel>(
                value: widget.preferences.volumeLevel,
                items: const [
                  DropdownMenuItem(
                      value: PulseVolumeLevel.quiet, child: Text('Baixo')),
                  DropdownMenuItem(
                      value: PulseVolumeLevel.normal, child: Text('Normal')),
                  DropdownMenuItem(
                      value: PulseVolumeLevel.loud, child: Text('Alto')),
                ],
                onChanged: (value) => value == null
                    ? null
                    : _change(widget.preferences.copyWith(volumeLevel: value)),
              ),
            ),
            SwitchListTile(
                minTileHeight: minimumHeight,
                title: const Text('Áudio mono'),
                subtitle:
                    const Text('Combina os canais esquerdo e direito em mono.'),
                value: widget.preferences.monoAudio,
                onChanged: (value) =>
                    _change(widget.preferences.copyWith(monoAudio: value))),
            SwitchListTile(
                minTileHeight: minimumHeight,
                title: const Text('Buscar letras sincronizadas'),
                subtitle: const Text(
                    'Envia título, artista e duração ao LRCLIB quando a letra embutida não tem tempos. Guarda a letra sincronizada neste dispositivo.'),
                value: widget.preferences.onlineSyncedLyrics,
                onChanged: (value) => _change(
                    widget.preferences.copyWith(onlineSyncedLyrics: value))),
          ],
        _SettingsSection.appearance => _appearanceControls(minimumHeight),
        _SettingsSection.startup => _startupControls(minimumHeight),
        _SettingsSection.storage => [
            ListTile(
                minTileHeight: minimumHeight,
                leading: const Icon(Icons.memory_rounded),
                title: const Text('Cache de capas em memória'),
                subtitle: const Text(
                    'Até 4 MB. Temporário; limpar não remove arquivos de música nem capas dos seus arquivos.')),
            ListTile(
                minTileHeight: minimumHeight,
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Limpar cache de capas'),
                subtitle: const Text(
                    'As miniaturas serão carregadas novamente quando necessário.'),
                onTap: widget.onClearArtwork),
            ListTile(
              minTileHeight: minimumHeight,
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Pasta de dados do Pulse'),
              subtitle: Platform.isAndroid
                  ? const Text('Dados privados do aplicativo no aparelho')
                  : Text(_pulseDataPath,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Platform.isWindows
                  ? TextButton(
                      onPressed: _openPulseDataFolder,
                      child: const Text('Abrir pasta'),
                    )
                  : null,
            ),
            if (Platform.isAndroid)
              const ListTile(
                leading: Icon(Icons.audio_file_outlined),
                title: Text('Músicas importadas'),
                subtitle: Text(
                    'O Pulse guarda cópias privadas dos MP3 ou Opus selecionados. Os arquivos originais continuam intactos.'),
              )
            else
              const ListTile(
                leading: Icon(Icons.download_outlined),
                title: Text('Downloads'),
                subtitle: Text(
                    '0 MB • o Pulse reproduz os arquivos locais na pasta original e não cria cópias.'),
              ),
          ],
        _SettingsSection.about => [
            ListTile(
                minTileHeight: minimumHeight,
                leading: const Icon(Icons.graphic_eq_rounded),
                title: const Text('Pulse'),
                subtitle:
                    const Text('Player de música local com servidor opcional')),
            ListTile(
                minTileHeight: minimumHeight,
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Versão'),
                subtitle:
                    Text('$pulseAppVersion • build $pulseAppBuildNumber')),
            ListTile(
                minTileHeight: minimumHeight,
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('Suas preferências ficam neste dispositivo'),
                subtitle: const Text(
                    'O catálogo local fica no dispositivo. A credencial do servidor é guardada no armazenamento seguro do sistema.')),
          ],
      };

  List<Widget> _jellyfinControls() {
    final connected = widget.jellyfin.connected;
    return [
      Padding(
        padding: const EdgeInsets.all(12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.jellyfin.sessionExpired
              ? 'A sessão ${widget.jellyfin.serverName} expirou. Entre novamente para atualizar a biblioteca.'
              : connected
                  ? 'Conectado como ${widget.jellyfin.username ?? 'usuário'}'
                  : 'O Pulse abre sem login. Conecte seu servidor de música para ouvir a biblioteca.'),
          const SizedBox(height: 12),
          if (!connected) ...[
            SegmentedButton<MusicServerKind>(
              segments: const [
                ButtonSegment(
                    value: MusicServerKind.jellyfin, label: Text('Jellyfin')),
                ButtonSegment(
                    value: MusicServerKind.navidrome, label: Text('Navidrome')),
              ],
              selected: {_serverKind},
              onSelectionChanged: _connecting
                  ? null
                  : (selection) {
                      setState(() {
                        _serverKind = selection.first;
                        _connectionMessage = null;
                        _savedServerSession =
                            widget.jellyfin.hasSavedSession(_serverKind);
                        if (_serverKind == MusicServerKind.navidrome &&
                            _server.text == JellyfinController.defaultServer) {
                          _server.text = 'https://navidrome.discovery.dev.br';
                        }
                      });
                    },
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _server,
            enabled: !connected && !_connecting,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Servidor HTTPS',
              border: OutlineInputBorder(),
            ),
          ),
          if (!connected) ...[
            const SizedBox(height: 12),
            FutureBuilder<bool>(
              future: _savedServerSession,
              builder: (context, snapshot) => snapshot.data == true
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        onPressed: _connecting
                            ? null
                            : () async {
                                setState(() {
                                  _connecting = true;
                                  _connectionMessage = null;
                                });
                                try {
                                  await widget.jellyfin
                                      .activateSavedSession(_serverKind);
                                } on Object {
                                  if (mounted) {
                                    setState(() => _connectionMessage =
                                        'Sessão salva indisponível. Entre com usuário e senha.');
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _connecting = false);
                                  }
                                }
                              },
                        icon: const Icon(Icons.lock_open_rounded),
                        label: const Text('Usar sessão salva'),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            TextField(
              controller: _user,
              enabled: !_connecting,
              decoration: const InputDecoration(
                  labelText: 'Usuário', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              enabled: !_connecting,
              onSubmitted: (_) => _loginJellyfin(),
              decoration: const InputDecoration(
                  labelText: 'Senha', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: _connecting ? null : _loginJellyfin,
                icon: const Icon(Icons.login_rounded),
                label: const Text('Conectar'),
              ),
              if (_serverKind == MusicServerKind.jellyfin)
                OutlinedButton.icon(
                  onPressed: _connecting ? null : _quickConnect,
                  icon: const Icon(Icons.phonelink_rounded),
                  label: const Text('Quick Connect'),
                ),
            ]),
          ] else ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed:
                    widget.jellyfin.loading ? null : widget.jellyfin.refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Atualizar biblioteca'),
              ),
              OutlinedButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => FractionallySizedBox(
                    heightFactor: .88,
                    child: PulseLibraryInsights(jellyfin: widget.jellyfin),
                  ),
                ),
                icon: const Icon(Icons.rule_folder_outlined),
                label: const Text('Qualidade da biblioteca'),
              ),
              TextButton.icon(
                onPressed: widget.jellyfin.disconnect,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Desconectar'),
              ),
              TextButton.icon(
                onPressed: widget.jellyfin.loading
                    ? null
                    : () => widget.jellyfin.disconnect(keepSavedSession: true),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Trocar servidor'),
              ),
            ]),
          ],
          if (_connecting || widget.jellyfin.loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_connectionMessage != null) ...[
            const SizedBox(height: 12),
            Text(_connectionMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
    ];
  }

  String get _pulseDataPath {
    final base = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        'Pasta local indisponível';
    return '$base${Platform.pathSeparator}PulseFlutter';
  }

  Future<void> _openPulseDataFolder() async {
    try {
      final directory = Directory(_pulseDataPath);
      await directory.create(recursive: true);
      await Process.start('explorer.exe', [directory.path]);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível abrir a pasta do Pulse.')));
      }
    }
  }

  List<Widget> _startupControls(double minimumHeight) => [
        ListTile(
          minTileHeight: minimumHeight,
          title: const Text('Abrir o Pulse ao entrar no Windows'),
          subtitle: const Text(
              'A opção é registrada somente neste usuário do Windows.'),
          trailing: DropdownButton<PulseStartupBehavior>(
            value: widget.preferences.startupBehavior,
            items: const [
              DropdownMenuItem(
                  value: PulseStartupBehavior.disabled,
                  child: Text('Desativado')),
              DropdownMenuItem(
                  value: PulseStartupBehavior.normal, child: Text('Normal')),
              DropdownMenuItem(
                  value: PulseStartupBehavior.minimized,
                  child: Text('Minimizado')),
            ],
            onChanged: (value) {
              if (value != null) _setStartupBehavior(value);
            },
          ),
        ),
        SwitchListTile(
          minTileHeight: minimumHeight,
          title: const Text('O botão Fechar envia à bandeja'),
          subtitle: const Text(
              'Quando ativado, o X envia o Pulse à bandeja. Minimizar mantém o Pulse na barra de tarefas.'),
          value: widget.preferences.closeToMinimize,
          onChanged: (value) async {
            try {
              await const MethodChannel('pulse/window')
                  .invokeMethod<void>('setCloseToMinimize', value);
              _change(widget.preferences.copyWith(closeToMinimize: value));
            } on Object {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Não foi possível atualizar o comportamento da janela.')));
              }
            }
          },
        ),
        ListTile(
          minTileHeight: minimumHeight,
          title: const Text('Sair do Pulse'),
          subtitle: const Text(
              'Encerra o aplicativo mesmo quando Fechar minimiza a janela.'),
          trailing: OutlinedButton.icon(
            onPressed: widget.onExit,
            icon: const Icon(Icons.exit_to_app_rounded),
            label: const Text('Sair'),
          ),
        ),
      ];

  Future<void> _setStartupBehavior(PulseStartupBehavior behavior) async {
    if (!Platform.isWindows) return;
    const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    try {
      if (behavior == PulseStartupBehavior.disabled) {
        final query =
            await Process.run('reg.exe', ['query', key, '/v', 'PulseFlutter']);
        if (query.exitCode == 0) {
          final result = await Process.run(
              'reg.exe', ['delete', key, '/v', 'PulseFlutter', '/f']);
          if (result.exitCode != 0) {
            throw const ProcessException(
                'reg.exe', [], 'Could not remove startup entry.');
          }
        }
      } else {
        final executable = Platform.resolvedExecutable;
        final launch = behavior == PulseStartupBehavior.minimized
            ? '"$executable" --pulse-startup-minimized'
            : '"$executable"';
        final result = await Process.run('reg.exe', [
          'add',
          key,
          '/v',
          'PulseFlutter',
          '/t',
          'REG_SZ',
          '/d',
          launch,
          '/f',
        ]);
        if (result.exitCode != 0) {
          throw const ProcessException(
              'reg.exe', [], 'Could not set startup entry.');
        }
      }
      _change(widget.preferences.copyWith(startupBehavior: behavior));
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Não foi possível salvar a inicialização do Pulse.')));
      }
    }
  }

  Future<void> _loginJellyfin() async {
    if (_user.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _connectionMessage = 'Informe usuário e senha.');
      return;
    }
    if (Uri.tryParse(_server.text.trim())?.host.toLowerCase() ==
            'navidrome.discovery.dev.br' &&
        _serverKind != MusicServerKind.navidrome) {
      _serverKind = MusicServerKind.navidrome;
    }
    setState(() {
      _connecting = true;
      _connectionMessage = null;
    });
    try {
      if (_serverKind == MusicServerKind.navidrome) {
        NavidromeClient.validateServer(_server.text);
      }
      await widget.jellyfin.connectWithPassword(
          _server.text, _user.text, _password.text,
          kind: _serverKind);
      _password.clear();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _connectionMessage = _connectionErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  String _connectionErrorMessage(Object error) {
    if (error is JellyfinException) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return 'Usuário ou senha recusados pelo ${_serverKind.name == 'navidrome' ? 'Navidrome' : 'Jellyfin'}.';
      }
      return 'O servidor respondeu com erro HTTP ${error.statusCode}. Confira o endereço e tente novamente.';
    }
    if (error is SocketException) {
      return 'Não foi possível alcançar o servidor. Confira o endereço e a conexão do PC.';
    }
    if (error is HandshakeException) {
      return 'A conexão HTTPS foi recusada. Confira o certificado do servidor.';
    }
    if (error is FormatException) return error.message;
    return 'Falha ao entrar no servidor. Confira o endereço e tente novamente.';
  }

  Future<void> _quickConnect() async {
    setState(() {
      _connecting = true;
      _connectionMessage = null;
    });
    try {
      final request = await widget.jellyfin.beginQuickConnect(_server.text);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Quick Connect'),
          content: Text(
              'No Jellyfin já conectado, abra Configurações > Quick Connect e autorize o código ${request.code}. Depois volte aqui.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                try {
                  final done = await widget.jellyfin
                      .finishQuickConnect(_server.text, request.secret);
                  if (!dialogContext.mounted) return;
                  if (done) {
                    Navigator.pop(dialogContext);
                  } else {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Aguardando autorização no Jellyfin.')));
                  }
                } on Object {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(
                        content: Text(
                            'Código expirado ou conexão indisponível. Tente novamente.')));
                  }
                }
              },
              child: const Text('Já autorizei'),
            ),
          ],
        ),
      );
    } on Object {
      if (mounted) {
        setState(() => _connectionMessage =
            'Quick Connect indisponível neste servidor. Use usuário e senha.');
      }
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  List<Widget> _appearanceControls(double minimumHeight) {
    final narrow = MediaQuery.sizeOf(context).width < 840;
    final themeSelector = SegmentedButton<PulseAppearance>(
        segments: const [
          ButtonSegment(value: PulseAppearance.dark, label: Text('Escuro')),
          ButtonSegment(value: PulseAppearance.light, label: Text('Claro')),
        ],
        selected: {
          widget.preferences.appearance
        },
        onSelectionChanged: (value) =>
            _change(widget.preferences.copyWith(appearance: value.first)));
    final densitySelector = DropdownButton<PulseDensity>(
        isExpanded: narrow,
        value: widget.preferences.density,
        items: const [
          DropdownMenuItem(
              value: PulseDensity.compact, child: Text('Compacto')),
          DropdownMenuItem(value: PulseDensity.standard, child: Text('Padrão')),
          DropdownMenuItem(
              value: PulseDensity.comfortable, child: Text('Confortável')),
        ],
        onChanged: (value) {
          if (value != null) {
            _change(widget.preferences.copyWith(density: value));
          }
        });
    if (narrow) {
      return [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Tema', style: Theme.of(context).textTheme.titleSmall)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Aplicação imediata',
                style: Theme.of(context).textTheme.bodySmall)),
        Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(width: double.infinity, child: themeSelector)),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child:
                Text('Paleta', style: Theme.of(context).textTheme.titleSmall)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Escolha as cores do Pulse',
                style: Theme.of(context).textTheme.bodySmall)),
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: _paletteSelector(narrow: true)),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Tamanho dos controles',
                style: Theme.of(context).textTheme.titleSmall)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Alvos de toque permanecem acessíveis',
                style: Theme.of(context).textTheme.bodySmall)),
        Padding(
            padding: const EdgeInsets.all(12),
            child: InputDecorator(
                decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                child: densitySelector)),
      ];
    }
    return [
      ListTile(
          minTileHeight: minimumHeight,
          title: const Text('Tema'),
          subtitle: const Text('Aplicação imediata'),
          trailing: themeSelector),
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Paleta', style: Theme.of(context).textTheme.titleSmall)),
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Escolha as cores do Pulse',
              style: Theme.of(context).textTheme.bodySmall)),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _paletteSelector(narrow: false)),
      ListTile(
          minTileHeight: minimumHeight,
          title: const Text('Tamanho dos controles'),
          subtitle: const Text('Alvos de toque permanecem acessíveis'),
          trailing: densitySelector),
    ];
  }

  Widget _paletteSelector({required bool narrow}) {
    final cards = PulsePalette.values
        .where((palette) =>
            Platform.isWindows ||
            (palette != PulsePalette.purpleDeepBlue &&
                palette != PulsePalette.desktopSmoke))
        .map((palette) => _paletteCard(palette))
        .toList(growable: false);
    if (narrow) {
      return Column(
        children: [
          for (final card in cards) ...[
            card,
            const SizedBox(height: 8),
          ],
        ],
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final cardWidth = (constraints.maxWidth - 8) / 2;
      final rows = (cards.length + 1) ~/ 2;
      return SizedBox(
        height: rows * 128.0 + (rows - 1) * 8.0,
        child: GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: cardWidth / 128,
          children: cards,
        ),
      );
    });
  }

  Widget _paletteCard(PulsePalette choice) {
    final (name, summary) = switch (choice) {
      PulsePalette.navyGreen => Platform.isWindows
          ? ('Frosted · Verde', 'Vidro fosco com detalhe verde')
          : ('Navy/Verde', 'Paleta original'),
      PulsePalette.redNavy => Platform.isWindows
          ? ('Frosted · Vermelho', 'Vidro fosco com detalhe vermelho')
          : ('Vermelho/Navy', 'Vermelho profundo'),
      PulsePalette.blueNavy => Platform.isWindows
          ? ('Frosted · Azul', 'Vidro fosco com detalhe azul')
          : ('Azul/Navy', 'Azul vívido'),
      PulsePalette.purpleDeepBlue => Platform.isWindows
          ? ('Frosted · Roxo', 'Vidro fosco com detalhe roxo')
          : ('Roxo/Azul escuro', 'Roxo profundo'),
      PulsePalette.desktopSmoke => (
          'Frosted · Neutro',
          'Vidro fosco sem cor forte'
        ),
    };
    final sample = PulsePaletteTheme(palette: choice, light: false);
    final selected = widget.preferences.palette == choice;
    final hovered = _hoveredPalette == choice;
    final focused = _focusedPalette == choice;
    final active = selected || hovered || focused;
    final colorScheme = Theme.of(context).colorScheme;
    final outline = Theme.of(context).brightness == Brightness.light
        ? colorScheme.onSurface
        : pulseDarkText;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Paleta $name${selected ? ', selecionada' : ''}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('palette-${choice.name}'),
          focusNode: _paletteFocusNodes[choice],
          borderRadius: BorderRadius.circular(10),
          onHover: (hovered) => setState(
            () => _hoveredPalette = hovered ? choice : null,
          ),
          onFocusChange: (focused) => setState(
            () => _focusedPalette = focused ? choice : null,
          ),
          onTap: () => _change(widget.preferences.copyWith(palette: choice)),
          child: Container(
            key: ValueKey('palette-card-surface-${choice.name}'),
            height: 128,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: hovered || focused
                  ? Color.alphaBlend(
                      colorScheme.onSurface.withValues(alpha: 0.08),
                      colorScheme.surfaceContainerHighest)
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? outline : colorScheme.outlineVariant,
                width: focused
                    ? 3
                    : active
                        ? 2
                        : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded,
                        size: 18, color: colorScheme.onSurface),
                ]),
                Text(summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                Row(children: [
                  _solidSwatch(sample.accent),
                  const SizedBox(width: 4),
                  _solidSwatch(sample.darkBase),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _gradientSwatch(
                        sample.selectionGradient, sample.accent),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _gradientSwatch(
                        sample.reverseGradient, sample.darkBase),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(
                  sample.isFrosted
                      ? 'Vidro fosco  ·  ${_hex(sample.accent)}'
                      : choice == PulsePalette.navyGreen
                          ? '#007D10  ·  #02060E'
                          : '${_hex(sample.accent)}  ↔  ${_hex(sample.darkBase)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _solidSwatch(Color color) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white54),
        ),
      );

  Widget _gradientSwatch(LinearGradient? gradient, Color solid) => Container(
        height: 22,
        decoration: BoxDecoration(
          color: gradient == null ? solid : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white54),
        ),
      );

  String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  Widget _sourceState(BuildContext context) {
    final (label, icon) = switch (widget.library.sourceState) {
      LibrarySourceState.notConfigured => (
          'Nenhuma pasta configurada',
          Icons.info_outline_rounded
        ),
      LibrarySourceState.available => (
          'Pasta disponível',
          Icons.check_circle_outline_rounded
        ),
      LibrarySourceState.disconnected => (
          'Pasta desconectada',
          Icons.cloud_off_outlined
        ),
      LibrarySourceState.readError => (
          'Erro ao ler a pasta',
          Icons.error_outline_rounded
        ),
      LibrarySourceState.partial => (
          'Leitura parcial',
          Icons.warning_amber_rounded
        ),
    };
    return ListTile(
        leading: Icon(icon),
        title: const Text('Estado da biblioteca'),
        subtitle: Text(label));
  }

  void _change(PulsePreferences value) async {
    try {
      await widget.onPreferencesChanged(value);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text(
                  'Não foi possível salvar essa preferência. O valor anterior foi mantido.')));
      }
    }
  }

  Widget _section(BuildContext context, String title, IconData icon,
          List<Widget> children) =>
      Card(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                        child: Row(children: [
                          Icon(icon, size: 20),
                          const SizedBox(width: 10),
                          Text(title,
                              style: Theme.of(context).textTheme.titleMedium)
                        ])),
                    ...children
                  ])));

  (String, String, IconData) _sectionInfo(_SettingsSection section) =>
      switch (section) {
        _SettingsSection.library => (
            'Biblioteca',
            'Pasta, reanálise e estado da coleção',
            Icons.library_music_outlined
          ),
        _SettingsSection.jellyfin => (
            'Servidor de música',
            'Conexão opcional com seu servidor de música',
            Icons.cloud_outlined
          ),
        _SettingsSection.playback => (
            'Reprodução',
            'Retomada e avanço automático',
            Icons.graphic_eq_rounded
          ),
        _SettingsSection.appearance => (
            'Aparência',
            'Tema e tamanho dos controles',
            Icons.palette_outlined
          ),
        _SettingsSection.startup => (
            'Inicialização e comportamento da janela',
            'Inicialização do Windows e botão Fechar',
            Icons.desktop_windows_outlined
          ),
        _SettingsSection.storage => (
            'Armazenamento',
            'Dados locais e cache temporário de capas',
            Icons.storage_outlined
          ),
        _SettingsSection.about => (
            'Sobre',
            'Versão e privacidade local',
            Icons.info_outline_rounded
          ),
      };
}
