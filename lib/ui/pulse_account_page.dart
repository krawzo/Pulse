import 'package:flutter/material.dart';
import 'dart:io';

import '../data/jellyfin_client.dart';
import '../data/navidrome_client.dart';
import '../state/jellyfin_controller.dart';

/// Personal Pulse account panel. Pulse uses the selected music server account
/// and does not maintain a separate account database or sign-up flow.
class PulseAccountPage extends StatefulWidget {
  const PulseAccountPage({
    super.key,
    required this.jellyfin,
    this.onConnected,
    this.onClose,
    this.forceSignIn = false,
  });

  final JellyfinController jellyfin;
  final VoidCallback? onConnected;
  final VoidCallback? onClose;
  final bool forceSignIn;

  @override
  State<PulseAccountPage> createState() => _PulseAccountPageState();
}

class _PulseAccountPageState extends State<PulseAccountPage> {
  late final TextEditingController _server =
      TextEditingController(text: widget.jellyfin.server);
  late final TextEditingController _user =
      TextEditingController(text: widget.jellyfin.username);
  final _password = TextEditingController();
  bool _submitting = false;
  bool _showPassword = false;
  late MusicServerKind _serverKind = widget.jellyfin.serverKind;
  late Future<bool> _savedSession =
      widget.jellyfin.hasSavedSession(_serverKind);
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_submitting) return;
    final server = _server.text.trim();
    final user = _user.text.trim();
    final password = _password.text;
    if (Uri.tryParse(server)?.host.toLowerCase() ==
            'navidrome.discovery.dev.br' &&
        _serverKind != MusicServerKind.navidrome) {
      _serverKind = MusicServerKind.navidrome;
    }
    try {
      if (_serverKind == MusicServerKind.navidrome) {
        NavidromeClient.validateServer(server);
      } else {
        JellyfinClient.validateServer(server);
      }
    } on FormatException {
      setState(() => _error = 'Informe o domínio HTTPS completo do servidor.');
      return;
    }
    if (user.isEmpty || password.isEmpty) {
      setState(() => _error = 'Informe usuário e senha.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.jellyfin
          .connectWithPassword(server, user, password, kind: _serverKind);
      _password.clear();
      widget.onConnected?.call();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _connectionErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _connectionErrorMessage(Object error) {
    if (error is JellyfinException) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return 'Usuário ou senha recusados pelo ${_serverKind == MusicServerKind.navidrome ? 'Navidrome' : 'Jellyfin'}.';
      }
      return 'O servidor respondeu com erro HTTP ${error.statusCode}.';
    }
    if (error is SocketException) {
      return 'Não foi possível alcançar o servidor. Confira a conexão do PC.';
    }
    if (error is HandshakeException) {
      return 'A conexão HTTPS foi recusada. Confira o certificado do servidor.';
    }
    return 'Não foi possível entrar. Confira servidor e conexão.';
  }

  Future<void> _restoreSavedSession() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.jellyfin.activateSavedSession(_serverKind);
      widget.onConnected?.call();
    } on Object {
      if (mounted) {
        setState(() => _error =
            'A sessão salva não está disponível. Entre com usuário e senha.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.jellyfin,
        builder: (context, _) => SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: ListView(
                shrinkWrap: true,
                keyboardDismissBehavior: Platform.isAndroid
                    ? ScrollViewKeyboardDismissBehavior.onDrag
                    : ScrollViewKeyboardDismissBehavior.manual,
                padding: const EdgeInsets.fromLTRB(26, 24, 26, 32),
                children: [
                  if (widget.onClose != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Fechar',
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  Center(
                    child: CircleAvatar(
                      radius: 38,
                      backgroundColor: const Color(0xFF1ED760),
                      foregroundImage: widget.jellyfin.profileImageUrl == null
                          ? null
                          : NetworkImage(widget.jellyfin.profileImageUrl!),
                      child: widget.jellyfin.connected
                          ? Text(
                              ((widget.jellyfin.username?.trim().isNotEmpty ??
                                          false)
                                      ? widget.jellyfin.username!.trim()
                                      : 'P')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800),
                            )
                          : const Icon(Icons.graphic_eq_rounded,
                              size: 38, color: Colors.black),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.forceSignIn
                        ? 'Reconectar ao ${widget.jellyfin.serverName}'
                        : widget.jellyfin.connected
                            ? widget.jellyfin.username ?? 'Sua conta'
                            : 'Entrar no Pulse',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.forceSignIn
                        ? 'Entre novamente para renovar a sessão e salvar a playlist.'
                        : widget.jellyfin.connected
                            ? 'Biblioteca conectada ao ${widget.jellyfin.serverName}'
                            : 'Use sua conta do servidor de música. O Pulse não cria contas.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 28),
                  if (widget.jellyfin.connected && !widget.forceSignIn) ...[
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: const Text('Servidor'),
                      subtitle: Text(widget.jellyfin.server),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: widget.jellyfin.loading
                          ? null
                          : widget.jellyfin.disconnect,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sair da conta'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: widget.jellyfin.loading
                          ? null
                          : () => widget.jellyfin
                              .disconnect(keepSavedSession: true),
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: const Text('Trocar servidor'),
                    ),
                  ] else ...[
                    SegmentedButton<MusicServerKind>(
                      segments: const [
                        ButtonSegment(
                            value: MusicServerKind.jellyfin,
                            label: Text('Jellyfin')),
                        ButtonSegment(
                            value: MusicServerKind.navidrome,
                            label: Text('Navidrome')),
                      ],
                      selected: {_serverKind},
                      onSelectionChanged: _submitting
                          ? null
                          : (selection) {
                              setState(() {
                                _serverKind = selection.first;
                                _error = null;
                                _savedSession = widget.jellyfin
                                    .hasSavedSession(_serverKind);
                                if (_serverKind == MusicServerKind.jellyfin &&
                                    _server.text.trim().isEmpty) {
                                  _server.text =
                                      JellyfinController.defaultServer;
                                } else if (_serverKind ==
                                        MusicServerKind.navidrome &&
                                    _server.text ==
                                        JellyfinController.defaultServer) {
                                  _server.text =
                                      'https://navidrome.discovery.dev.br';
                                }
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<bool>(
                      future: _savedSession,
                      builder: (context, snapshot) => snapshot.data == true
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: OutlinedButton.icon(
                                onPressed:
                                    _submitting ? null : _restoreSavedSession,
                                icon: const Icon(Icons.lock_open_rounded),
                                label: const Text('Usar sessão salva'),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    TextField(
                      controller: _server,
                      enabled: !_submitting,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.url],
                      decoration: const InputDecoration(
                        labelText: 'Domínio do servidor',
                        hintText: 'https://seu-servidor.com',
                        prefixIcon: Icon(Icons.dns_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _user,
                      enabled: !_submitting,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'Usuário',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      enabled: !_submitting,
                      obscureText: !_showPassword,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _signIn(),
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip:
                              _showPassword ? 'Ocultar senha' : 'Mostrar senha',
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                          icon: Icon(_showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submitting ? null : _signIn,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _submitting
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ))
                            : const Text('Entrar'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}
