import 'dart:async';
import 'dart:io';

import 'package:dart_cast/dart_cast.dart' show CastDevice, CastProtocol;
import 'package:flutter/foundation.dart';

import '../connect/pulse_cast_output.dart';
import '../connect/pulse_media_server.dart';
import '../connect/pulse_output.dart';
import '../connect/pulse_peer_output.dart';
import '../connect/pulse_peer_receiver.dart';
import '../connect/pulse_peer_trust.dart';
import '../connect/pulse_remote_playback.dart';
import '../domain/audio_track.dart';
import 'jellyfin_controller.dart';
import 'playback_controller.dart';
import 'pulse_cast_discovery.dart';
import 'pulse_peer_discovery.dart';

/// Owns the active device handoff and the temporary media server.
class PulseConnectController extends ChangeNotifier {
  PulseConnectController({
    required PlaybackController playback,
    required JellyfinController jellyfin,
  })  : _playback = playback,
        _jellyfin = jellyfin,
        _server = PulseMediaServer(jellyfinStreamUrl: jellyfin.streamUrl) {
    _trust = PulsePeerTrust();
    _receiver = PulsePeerReceiver(
        playback: playback, jellyfin: jellyfin, trust: _trust);
    _playback.addListener(_onPlaybackChanged);
    _jellyfin.addListener(_onJellyfinChanged);
    _receiver.onApprovalRequested = (name, address) async {
      final callback = onPeerApprovalRequested;
      return callback == null ? false : callback(name, address);
    };
    _receiver.onReverseRequested = (peerId) async {
      if (!selectedRemote || _deviceId != peerId) return false;
      await returnToComputer();
      return !selectedRemote;
    };
    unawaited(_initializePeer());
  }

  final PlaybackController _playback;
  final JellyfinController _jellyfin;
  final PulseMediaServer _server;
  late final PulsePeerReceiver _receiver;
  late final PulsePeerTrust _trust;
  final PulsePeerDiscovery peers = PulsePeerDiscovery();
  PulsePeerApproval? onPeerApprovalRequested;
  PulseRemotePlayback? _activeOutput;
  String? _deviceName;
  String? _deviceId;
  String? _errorMessage;
  bool _busy = false;
  bool _disposed = false;
  bool _identityReady = false;
  PulseOutputPhase? _lastRemotePhase;
  String? _lastPlaybackError;

  bool get busy => _busy;
  bool get selectedRemote => _activeOutput != null && _playback.isRemoteOutput;
  bool get connectionLost =>
      selectedRemote &&
      (_playback.remoteOutput?.state.phase == PulseOutputPhase.disconnected ||
          _playback.remoteOutput?.state.phase == PulseOutputPhase.error);
  bool get connected => selectedRemote && !connectionLost;
  bool get playing => selectedRemote && _playback.isPlaying;
  String? get deviceName => _deviceName;
  bool isSelected(PulseCastDevice device) =>
      selectedRemote && _deviceId == device.id;
  String? get errorMessage =>
      _errorMessage ?? (connectionLost ? _playback.errorMessage : null);
  PulseMediaServerStatus get mediaServerStatus => _server.status;
  bool isSelectedPeer(PulsePeer peer) => selectedRemote && _deviceId == peer.id;

  Future<void> _initializePeer() async {
    try {
      await _trust.load();
      if (_disposed) return;
      _identityReady = true;
      _onJellyfinChanged();
      await _startPeerReceiver();
      await peers.start();
    } on Object {
      _errorMessage = 'Não foi possível preparar a identidade deste Pulse.';
      if (!_disposed) notifyListeners();
    }
  }

  void _onJellyfinChanged() {
    if (_disposed || !_identityReady) return;
    peers.configure(
        deviceId: _trust.deviceId,
        accountFingerprint: _jellyfin.accountFingerprint);
  }

  Future<void> _startPeerReceiver() async {
    final controlPort = await _receiver.start();
    if (!_disposed) await peers.setControlPort(controlPort);
  }

  Future<void> connectToPeer(PulsePeer peer) async {
    if (_disposed) throw StateError('Pulse Connect foi encerrado.');
    if (_busy) return;
    if (_jellyfin.accountFingerprint == null) {
      _errorMessage =
          'Entre na sua conta Jellyfin para localizar outros Pulse.';
      notifyListeners();
      return;
    }
    final current = _playback.currentTrack;
    if (current?.id.startsWith('pulse-incoming:') == true &&
        current?.source != AudioSource.jellyfin) {
      _errorMessage =
          'Para inverter a saída, toque uma faixa Jellyfin disponível nos dois aparelhos.';
      notifyListeners();
      return;
    }
    if (selectedRemote && _deviceId == peer.id) return;
    if (selectedRemote) await returnToComputer();
    if (selectedRemote || _busy) return;
    if (peer.controlPort == null) {
      _errorMessage = 'Atualize o Pulse no outro aparelho para conectar.';
      notifyListeners();
      return;
    }
    _busy = true;
    _errorMessage = null;
    notifyListeners();
    PulseRemotePlayback? candidate;
    PulsePeerOutput? output;
    final wasPlayingBeforePair = _playback.isPlaying;
    try {
      output = await PulsePeerOutput.pair(peer,
          trust: _trust, account: _jellyfin.accountFingerprint!);
      if (wasPlayingBeforePair && !_playback.isPlaying) {
        await _playback.togglePlaybackIfPaused();
      }
      final bindAddress = output.senderAddress ??
          await PulseMediaServer.findBindAddressForReceiver(
            receiverAddress: peer.address,
            receiverPort: peer.controlPort!,
          );
      await _server.start(
        bindAddress: bindAddress,
        receiverAddress: peer.address,
      );
      candidate = PulseRemotePlayback(
        output: output,
        mediaUriFor: (track) async => _server.mediaUriFor(track),
        mimeTypeFor: _server.mimeTypeFor,
      );
      await _playback.selectRemoteOutput(candidate);
      _activeOutput = candidate;
      _deviceName = peer.name;
      _deviceId = peer.id;
    } on Object catch (error) {
      _errorMessage = 'Não foi possível conectar ao outro Pulse: $error';
      if (candidate != null) {
        try {
          await candidate.dispose();
        } on Object {/* Keep original error. */}
      } else if (output != null) {
        try {
          await output.dispose();
        } on Object {/* Keep original error. */}
      }
      await _server.stop();
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Moves an independent Jellyfin queue to another trusted Pulse on this LAN.
  Future<void> continueOnPeer(PulsePeer peer) async {
    if (_disposed || _busy) return;
    final account = _jellyfin.accountFingerprint;
    final queue = _playback.queue;
    final index = _playback.currentIndex;
    if (account == null ||
        peer.controlPort == null ||
        selectedRemote ||
        queue.isEmpty ||
        queue.length > 500 ||
        index < 0 ||
        index >= queue.length ||
        queue.any((track) => track.source != AudioSource.jellyfin)) {
      _errorMessage =
          'Para continuar em outro aparelho, use uma fila Jellyfin de até 500 faixas.';
      notifyListeners();
      return;
    }
    _busy = true;
    _errorMessage = null;
    notifyListeners();
    PulsePeerOutput? output;
    var pausedForTransfer = false;
    try {
      output =
          await PulsePeerOutput.pair(peer, trust: _trust, account: account);
      final position = _playback.position;
      final wasPlaying = _playback.isPlaying;
      if (wasPlaying) {
        await _playback.pauseIfPlaying();
        pausedForTransfer = true;
      }
      await output.handOffQueue(
          queue.map((track) => track.path).toList(growable: false),
          index,
          position,
          wasPlaying);
      pausedForTransfer = false;
    } on Object catch (error) {
      _errorMessage = 'Não foi possível continuar no outro Pulse: $error';
      if (pausedForTransfer) await _playback.togglePlaybackIfPaused();
    } finally {
      await output?.dispose();
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Transfers the selected track only after the TV confirms PLAYING.
  /// If any step fails, the local output stays selected.
  Future<void> connectToCast(PulseCastDevice device) async {
    if (_disposed) throw StateError('Pulse Connect foi encerrado.');
    if (_busy) return;
    if (selectedRemote) {
      throw StateError('Volte para este computador antes de trocar de TV.');
    }
    if (_playback.currentTrack == null) {
      _errorMessage = 'Escolha uma faixa antes de conectar à TV.';
      notifyListeners();
      return;
    }
    _busy = true;
    _errorMessage = null;
    notifyListeners();

    PulseRemotePlayback? candidate;
    try {
      final receiverAddress = _resolveIpv4(device);
      final bindAddress = await PulseMediaServer.findBindAddressForReceiver(
        receiverAddress: receiverAddress,
        receiverPort: device.port,
      );
      await _server.start(
        bindAddress: bindAddress,
        receiverAddress: receiverAddress,
      );
      final output = PulseCastOutput(CastDevice(
        id: device.id,
        name: device.name,
        protocol: CastProtocol.chromecast,
        address: receiverAddress,
        port: device.port,
      ));
      candidate = PulseRemotePlayback(
        output: output,
        mediaUriFor: (track) async => _server.mediaUriFor(track),
        mimeTypeFor: _server.mimeTypeFor,
      );
      await _playback.selectRemoteOutput(candidate);
      _activeOutput = candidate;
      _deviceName = device.name;
      _deviceId = device.id;
    } on Object catch (error) {
      _errorMessage = 'Não foi possível tocar na TV: $error';
      if (candidate != null) {
        try {
          await candidate.dispose();
        } on Object {
          // The original output remains selected on handoff failure.
        }
      }
      await _server.stop();
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Returns at the remote position, then revokes the temporary URLs.
  Future<void> returnToComputer() async {
    if (_disposed || _busy || !selectedRemote) return;
    _busy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _playback.returnToLocalOutput();
      final previous = _activeOutput;
      _activeOutput = null;
      _deviceName = null;
      _deviceId = null;
      if (previous != null) await previous.dispose();
      await _server.stop();
    } on Object catch (error) {
      _errorMessage = 'Não foi possível voltar ao computador: $error';
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  InternetAddress _resolveIpv4(PulseCastDevice device) {
    final address = device.address == null
        ? null
        : InternetAddress.tryParse(device.address!);
    if (address == null || address.type != InternetAddressType.IPv4) {
      throw StateError('A TV não anunciou um endereço IPv4 nesta rede.');
    }
    return address;
  }

  void _onPlaybackChanged() {
    if (_disposed) return;
    final phase = _playback.remoteOutput?.state.phase;
    final error = _playback.errorMessage;
    if (_lastRemotePhase == phase && _lastPlaybackError == error) return;
    _lastRemotePhase = phase;
    _lastPlaybackError = error;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _playback.removeListener(_onPlaybackChanged);
    _jellyfin.removeListener(_onJellyfinChanged);
    peers.dispose();
    unawaited(_receiver.dispose());
    final active = _activeOutput;
    _activeOutput = null;
    if (active != null) {
      unawaited(active
          .stop()
          .catchError((Object _) {})
          .then((_) => active.dispose().catchError((Object _) {})));
    }
    _server.dispose();
    super.dispose();
  }
}
