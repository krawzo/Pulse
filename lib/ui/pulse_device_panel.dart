import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/pulse_theme.dart';
import '../state/pulse_cast_discovery.dart';
import '../state/pulse_connect_controller.dart';
import '../state/pulse_peer_discovery.dart';
import '../state/playback_controller.dart';

/// Shows this device, other Pulse receivers and Cast TVs on the local network.
class PulseDevicePanel extends StatefulWidget {
  const PulseDevicePanel({
    super.key,
    required this.onClose,
    this.connect,
    this.playback,
  });

  final VoidCallback onClose;
  final PulseConnectController? connect;
  final PlaybackController? playback;

  @override
  State<PulseDevicePanel> createState() => _PulseDevicePanelState();
}

class _PulseDevicePanelState extends State<PulseDevicePanel> {
  static const _androidMulticast = MethodChannel('pulse/cast_discovery');
  final _discovery = PulseCastDiscovery();
  Timer? _volumeDebounce;
  double? _draggingRemoteVolume;

  @override
  void initState() {
    super.initState();
    unawaited(_startDiscovery());
  }

  Future<void> _startDiscovery() async {
    var lockAcquired = false;
    if (Platform.isAndroid) {
      try {
        await _androidMulticast.invokeMethod<void>('acquire');
        lockAcquired = true;
      } on Object {
        // A failed lock is surfaced by the individual discovery services.
      }
    }
    if (!mounted) {
      if (lockAcquired) {
        unawaited(_androidMulticast.invokeMethod<void>('release'));
      }
      return;
    }
    unawaited(_discovery.scan());
    await widget.connect?.peers.refresh();
  }

  @override
  void dispose() {
    _volumeDebounce?.cancel();
    if (Platform.isAndroid) {
      unawaited(_androidMulticast.invokeMethod<void>('release'));
    }
    _discovery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localDevice = Platform.isAndroid ? 'Este celular' : 'Este computador';
    final palette = PulsePaletteTheme.of(context);
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: Listenable.merge([
        _discovery,
        if (widget.connect case final connect?) connect,
        if (widget.connect case final connect?) connect.peers,
        if (Platform.isAndroid && widget.playback != null) widget.playback!,
      ]),
      builder: (context, _) => SizedBox.expand(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Conectar a um dispositivo',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Procurar dispositivos novamente',
                    onPressed: _discovery.scanning
                        ? null
                        : () {
                            _discovery.scan();
                            unawaited(widget.connect?.peers.refresh());
                          },
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Fechar dispositivos',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            if (widget.connect?.errorMessage case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                child: Text(
                  error,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.connect?.selectedRemote == true
                      ? Colors.transparent
                      : palette.selected,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  onTap: widget.connect?.selectedRemote == true &&
                          widget.connect?.busy == false
                      ? () async => widget.connect!.returnToComputer()
                      : null,
                  leading: Icon(Icons.computer_rounded,
                      color: widget.connect?.selectedRemote == true
                          ? null
                          : palette.accent),
                  title: Text(
                    localDevice,
                    style: TextStyle(
                      color: widget.connect?.selectedRemote == true
                          ? colors.onSurface
                          : palette.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    widget.connect?.selectedRemote == true
                        ? 'Toque para trazer a música de volta'
                        : 'Reprodução atual',
                    style: TextStyle(
                        color: colors.onSurface.withValues(alpha: .65)),
                  ),
                  trailing: widget.connect?.selectedRemote == true
                      ? null
                      : Icon(Icons.check_rounded, color: palette.accent),
                ),
              ),
            ),
            Expanded(
              child: (widget.connect?.peers.peers.isEmpty ?? true) &&
                      widget.connect?.selectedRemote == true
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Text(
                          'Saída ativa: ${widget.connect?.deviceName}. Use “$localDevice” para trazer a música de volta.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : (widget.connect?.peers.peers.isEmpty ?? true)
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cast_rounded,
                                  size: 38,
                                  color:
                                      colors.onSurface.withValues(alpha: .48),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _discovery.scanning
                                      ? 'Procurando aparelhos Pulse…'
                                      : widget.connect?.peers.error ??
                                          _discovery.error ??
                                          'Nenhum Pulse da mesma conta Jellyfin encontrado',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Entre na mesma conta Jellyfin nos dois aparelhos e mantenha-os na mesma rede local. No Windows, permita o Pulse na rede privada.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: colors.onSurface
                                            .withValues(alpha: .65),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                              child: Text(
                                'Encontrados na rede',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                            for (final peer in widget.connect?.peers.peers ??
                                const <PulsePeer>[])
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: widget.connect?.isSelectedPeer(peer) ==
                                          true
                                      ? palette.selected
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ListTile(
                                  leading: Icon(
                                      peer.platform == 'windows'
                                          ? Icons.computer_rounded
                                          : Icons.smartphone_rounded,
                                      color: widget.connect
                                                  ?.isSelectedPeer(peer) ==
                                              true
                                          ? palette.accent
                                          : null),
                                  title: Text('Pulse em ${peer.name}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    widget.connect?.isSelectedPeer(peer) == true
                                        ? widget.connect?.connectionLost == true
                                            ? 'Conexão perdida'
                                            : widget.connect?.playing == true
                                                ? 'Reproduzindo neste aparelho'
                                                : 'Aparelho selecionado • pausado'
                                        : peer.controlPort == null
                                            ? 'Atualize o Pulse neste aparelho'
                                            : widget.connect?.busy == true
                                                ? 'Aguardando autorização…'
                                                : 'Toque para reproduzir • confirme só na primeira vez',
                                  ),
                                  trailing: widget.connect
                                              ?.isSelectedPeer(peer) ==
                                          true
                                      ? Icon(Icons.check_rounded,
                                          color: palette.accent)
                                      : widget.playback?.currentTrack != null &&
                                              peer.controlPort != null
                                          ? IconButton(
                                              tooltip:
                                                  'Continuar a fila neste aparelho',
                                              icon: const Icon(
                                                  Icons.move_up_rounded),
                                              onPressed: widget.connect?.busy ==
                                                      true
                                                  ? null
                                                  : () => widget.connect
                                                      ?.continueOnPeer(peer),
                                            )
                                          : null,
                                  onTap: widget.connect == null ||
                                          widget.connect!.busy ||
                                          peer.controlPort == null
                                      ? null
                                      : () =>
                                          widget.connect!.connectToPeer(peer),
                                ),
                              ),
                            for (final device in const <PulseCastDevice>[])
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color:
                                      widget.connect?.isSelected(device) == true
                                          ? palette.selected
                                          : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ListTile(
                                  onTap: widget.connect == null ||
                                          widget.connect!.busy ||
                                          widget.connect!.selectedRemote
                                      ? null
                                      : () async =>
                                          widget.connect!.connectToCast(device),
                                  leading: Icon(Icons.tv_rounded,
                                      color:
                                          widget.connect?.isSelected(device) ==
                                                  true
                                              ? palette.accent
                                              : null),
                                  title: Text(device.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    widget.connect?.isSelected(device) == true
                                        ? widget.connect?.connectionLost == true
                                            ? 'Conexão perdida'
                                            : widget.connect?.playing == true
                                                ? 'Reproduzindo nesta TV'
                                                : 'TV selecionada • pausado'
                                        : widget.connect?.busy == true
                                            ? 'Conectando…'
                                            : widget.connect == null
                                                ? 'Google Cast • disponível na rede'
                                                : 'Google Cast • tocar nesta TV',
                                  ),
                                  trailing:
                                      widget.connect?.isSelected(device) == true
                                          ? Icon(Icons.check_rounded,
                                              color: palette.accent)
                                          : null,
                                ),
                              ),
                          ],
                        ),
            ),
            if (Platform.isAndroid) _buildRemoteVolume(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Text(
                widget.connect?.connectionLost == true
                    ? 'A conexão com ${widget.connect?.deviceName} caiu. Use “$localDevice” para voltar.'
                    : widget.connect?.selectedRemote == true
                        ? 'A música está em ${widget.connect?.deviceName}. O Pulse controla a reprodução; transição gradual fica indisponível na saída remota.'
                        : widget.connect?.busy == true
                            ? 'Aguardando o aparelho confirmar a reprodução…'
                            : widget.connect == null
                                ? 'A música continua em $localDevice.'
                                : 'Selecione outro Pulse ou uma TV Google Cast para transferir a faixa.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurface.withValues(alpha: .65),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteVolume(BuildContext context) {
    final playback = widget.playback;
    final connected = widget.connect?.connected == true && playback != null;
    final current = (_draggingRemoteVolume ?? playback?.volume ?? 1.0)
        .clamp(0.0, 1.0)
        .toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            connected
                ? 'Volume de ${widget.connect?.deviceName}'
                : 'Volume do dispositivo',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          Row(children: [
            Icon(
              current == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              size: 20,
            ),
            Expanded(
              child: Slider(
                value: current,
                onChanged: !connected
                    ? null
                    : (value) {
                        setState(() => _draggingRemoteVolume = value);
                        _volumeDebounce?.cancel();
                        _volumeDebounce = Timer(
                          const Duration(milliseconds: 80),
                          () => unawaited(playback.setVolume(value)),
                        );
                      },
                onChangeEnd: !connected
                    ? null
                    : (value) {
                        _volumeDebounce?.cancel();
                        unawaited(playback.setVolume(value));
                        setState(() => _draggingRemoteVolume = null);
                      },
              ),
            ),
            SizedBox(
              width: 42,
              child:
                  Text('${(current * 100).round()}%', textAlign: TextAlign.end),
            ),
          ]),
          if (!connected)
            Text('Conecte outro aparelho para ajustar o volume dele.',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
