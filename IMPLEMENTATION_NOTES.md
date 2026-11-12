# Pulse implementation r17–r19

## r19 — mitigação do crash nativo no Windows

O WER da r18 indicou `0xc0000005` em `flutter_windows.dll+0x3c1ca`. O DLL do SDK local tem o mesmo SHA-256 do pacote executado; seu PDB simboliza esse offset em `AccessibilityBridge::CreateRemoveReparentedNodesUpdate`, `accessibility_bridge.cc:229`, na leitura de `child->parent()->id()`. O issue aberto `flutter/flutter#175041` documenta a mesma função e o workaround de `ExcludeSemantics` no `MaterialApp`. A r19 aplica esse limite apenas no Windows, com opção de reativação por `--enable-windows-accessibility`. O problema nativo do engine não foi corrigido em sua origem; leitores de tela ficam sem a árvore do Pulse por padrão. Os controladores e dados não foram modificados.

O script `tools/probe_windows_maximize.ps1` testa a janela Release de verdade, alternando maximizar/restaurar e consultando UI Automation. Por padrão usa perfis isolados vazio e com 200 faixas sintéticas; `-UseCurrentProfile` usa o perfil real. O teste no computador em que a r18 fechou ainda é necessário para validar a mitigação naquele ambiente.

## r18 — desktop

- Flutter foi mantido. `PulseDesktopLibrarySidebar`, `PulseCollectionHero` e `PulseQueuePanel` atendem às três regiões sem introduzir outro runtime.
- Busca/ordenação da lateral operam sobre os dados carregados. A lateral permanece visível em Configurações; o filtro de destino não esvazia a lista nessa tela.
- O dock controla o volume pela instância atual de áudio, e a fila no painel direito lê a mesma fila do controlador. O comportamento de fila em folha inferior continua disponível em larguras menores.
- Capas locais existentes continuam sob leitura; o hero usa a imagem como origem para um gradiente quando disponível. Não há modificação de MP3, catálogo, playlists ou sessão Jellyfin pelo redesenho.
- Os testes visuais incluem 21 capturas r18 (7 estados × 3 resoluções). São fixtures sintéticas; não comprovam audição física, conta real Jellyfin nem uso manual do EXE.

## Histórico r17

- `JellyfinClient` uses the Jellyfin API with MediaBrowser authorization in request headers. Passwords are sent only to `Users/AuthenticateByName`; a Quick Connect option uses initiate, status and authentication routes.
- `JellyfinController` restores an optional session, loads paginated audio items plus artists and playlists, maps remote favorites, and serves authenticated audio and artwork through an ephemeral loopback proxy. Media URLs contain a random local path, never the Jellyfin token. The proxy only accepts IDs present in the loaded catalog.
- `WindowsSecureSessionStore` encrypts the session file for the current Windows user using DPAPI. The portable source has no SDK, cache or credentials.
- The existing local library stays independent. Tracks carry a source marker; remote tracks can enter playback queues and the combined favorites view. Remote checkpoints are restored after the optional Jellyfin catalog loads, without autoplay.
- Verified in this workspace: Flutter analyze, 64 Flutter tests including API mocks and DPAPI round trip, Windows Release build, and 1280×800 / 1920×1080 goldens. Public server info returned Player / Jellyfin 10.11.11 and Quick Connect enabled. The supplied OpenAPI URL returned 404.
- Not verified: a real account login or Quick Connect approval, actual Jellyfin audio playback and image delivery, or manual execution of the packaged EXE. These require a user session on the server and Windows runtime review.

## Referência Spotify — opções de reprodução (13/10/2026)

- Referência examinada: instalação local em `%APPDATA%\Spotify`, versão `1.3.4.258`; `Apps\xpui.spa` (SHA-256 `19be39b9f8da51a5e766699bc0e7a8bf6dc6f09b1b733a2d8feb4cb2e1ce0608`). A análise estática REA do conteúdo JavaScript foi registrada em `ev_22a7b55b6ec99b692b016431a36ab4b05dd2fc90b37071e36e5f06a8b8994caa`; o módulo da página de configurações em `ev_157eb2598a91b1592d4aa8f5fe8d28f24c19d5b9515bd655b2ddfabc332ca937`. A cobertura semântica geral ficou parcial por limites de recursos, embora o módulo de configurações tenha sido analisado sem erro de parse.
- A interface de configurações liga `playback.audioCrossfade` a `playback.audioCrossfadeMs`; o controle de duração vai de 0 a 12 s e se move em passos de 1 s. `playback.monoAudio` controla o downmix mono. `quality.normalizeVolume` e `quality.volumeLevel` controlam normalização e os perfis silencioso, normal e alto. Esses nomes são observações da camada de interface empacotada, não confirmação da implementação nativa nem de uma sessão em execução.
- Automix é um controle separado (`playback.autoMix`) e a própria descrição o limita a playlists selecionadas. A transição de playlist pode carregar `automix.auto_transition_recipe`: a interface decodifica a receita, verifica velocidades/identidade do par de faixas e usa a sobreposição e os tempos A/B; sem receita correspondente, pede ao backend uma transição composta para o par. Portanto, Automix do Spotify depende de dados específicos de cada par e de suporte do backend; não é equivalente a apenas ligar o crossfade global.
- Implicação para Pulse: crossfade geral, downmix mono e normalização por faixa são DSP reproduzível localmente. O Automix deve permanecer distinto: uma implementação fiel exige dados de batida/tempo/velocidade e lógica de transição por par. O modelo `AudioTrack` atual não tem esses dados; qualquer Automix sem análise de áudio seria uma aproximação e deve ser apresentada como tal.
- Alteração de produto após essa análise: o controle Pulse de Automix fica visível e desativado com explicação até existir análise/receita por par; duração do crossfade passa a aceitar 0–12 s em passos de 1 s, como o controle observado no Spotify. Isso evita apresentar o booleano de Automix, que não tinha efeito no controlador, como uma função pronta.
- Limites da investigação: REA identificou `Spotify.exe` e `Spotify.dll`, mas não há provedor nativo configurado para decompilar o código PE. A inspeção do `.spa` só observou JavaScript estático; não executamos o Spotify nem observamos mudanças de áudio em runtime. O inventário REA do `.spa` também recusou a entrada ZIP `/` como caminho inseguro; a análise JS posterior foi feita sobre uma extração temporária com caminhos normalizados e sem entradas absolutas ou `..`.
