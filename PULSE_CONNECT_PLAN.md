# Pulse Connect — plano por etapas

## Objetivo

Uma única lista de saídas no Pulse, com o computador atual, TVs Google Cast e,
mais adiante, outros computadores com Pulse. A seleção deve transferir áudio,
fila, posição e controles de forma verificável. A música local continua no disco
original; credenciais Jellyfin permanecem somente no computador do usuário.

## Etapa 1 — descoberta

- O painel consulta `_googlecast._tcp.local` por mDNS apenas quando aberto ou
  atualizado pelo usuário.
- Só mostra TVs que responderam com registros de serviço; “Este computador”
  continua selecionado.
- A descoberta está implementada em `PulseCastDiscovery` e `PulseDevicePanel`.
  A seleção agora inicia a etapa 2; o Pulse só marca a TV como saída após
  confirmação de reprodução recebida dela.
- Falhas de rede ou ausência de aparelhos aparecem no próprio painel. Nenhuma
  regra de firewall ou configuração do Windows é alterada automaticamente.

## Etapa 2 — tocar em uma TV Google Cast

- O emissor Cast para Windows estabelece sessão e lê o estado real da TV.
  O SDK oficial de emissor atende Web, Android e iOS; para Flutter Windows,
  o protótipo usa `dart_cast` 0.7.4 apenas para o canal Cast V2 com framing
  correto; o envio de áudio e o estado estão encapsulados em `PulseCastSender`.
  Ele importa uma API interna fixada nessa versão, que exige revisão antes de
  atualizar a dependência.
- Usar servidor HTTP temporário acessível apenas na rede privada escolhida,
  com URL curta, imprevisível e válida somente durante a sessão. Atender GET,
  HEAD e Range. Para faixas Jellyfin, retransmitir o áudio sem expor o token
  Jellyfin à TV. Para faixas locais, ler o arquivo sem modificá-lo.
  `PulseMediaServer` implementa essa origem temporária e está ligada à sessão
  Cast. Apenas o IP da TV escolhida pode acessar URLs daquela sessão.
- Pausar a saída local ao iniciar a TV. Controles, duração e posição exibidos
  devem refletir confirmações da TV, não apenas cliques no Pulse.
- Ao desconectar ou perder a TV, oferecer retorno ao computador na mesma faixa
  e posição. Fila, repetição e shuffle precisam manter semântica consistente.
- Crossfade e Automix ficam indisponíveis na saída remota até haver mecanismo
  equivalente confirmado; o volume deve usar o estado do receptor.

### Estado atual da etapa 2

O fluxo de seleção, servidor de mídia, comandos Cast, retorno ao computador e
fila foi implementado em código. A análise estática passou. **Ainda falta a
prova em uma TV real com arquivos locais e faixas Jellyfin**, incluindo os
formatos suportados pela TV e a entrada do Windows Firewall. O painel deve
mostrar erro e manter o som local quando a TV não confirmar `PLAYING`.
O áudio destinado à TV percorre HTTP na rede local; segredo temporário, IP
restrito e encerramento da sessão reduzem exposição, mas não oferecem sigilo
contra alguém que consiga observar o tráfego da LAN.
O canal Cast V2 do pacote aceita o certificado autoassinado do receptor sem
validar identidade criptográfica. Por isso esta etapa pressupõe uma rede local
de confiança; o pareamento autenticado da etapa 3 terá outro modelo de ameaça.

## Etapa 3 — outro Pulse como receptor

O contrato de saída e estado (`PulseOutput`) já está no projeto; a descoberta,
o pareamento e o receptor em outro computador ainda não foram implementados.

- Descoberta e identidade próprias, distintas de Google Cast. Outro Pulse
  precisa estar instalado e ativo no computador receptor.
- Pareamento explícito no receptor, com segredo de sessão temporário e comandos
  autenticados. Nunca aceitar reprodução ou listar biblioteca de outro aparelho
  apenas porque ele está na mesma rede.
- Reaproveitar a camada de origem HTTP e o modelo de sessão da etapa 2, mas
  transmitir para um receptor Pulse. Não copiar o protocolo fechado Spotify
  Connect nem depender de uma conta Spotify.
- A saída ativa deve fornecer estado versionado (`sessionId`, revisão, faixa,
  posição, duração, tocando, volume e erro); quando remoto, o receptor é a
  autoridade dos controles mostrados pelo Pulse.
- Fazer handoff em duas fases: preparar mídia e posição no receptor, confirmar
  início, então pausar a origem. Falha no preparo mantém o áudio na origem.
- Descobrir `_pulseconnect._tcp.local` sem anunciar caminhos ou credenciais;
  parear com confirmação nos dois computadores antes de aceitar comandos.

## Limites observados no código atual

- `PlaybackController` usa um único `media_kit.Player` local para fila e
  controles. Uma saída remota requer um transporte selecionável e estado remoto
  separado.
- O proxy Jellyfin atende `127.0.0.1`; a TV não consegue acessar esse endereço.
- A descoberta por mDNS identifica aparelhos, mas não demonstra que a TV
  aceitará um codec ou tocará uma faixa. A reprodução ainda precisa ser
  confirmada numa TV real.

## Referência investigada com REA

- Observado no pacote instalado do Spotify 1.3.4.258: o botão da barra abre
  `DEVICE-PICKER` (evidência REA
  `ev_44fa7cfa99d908cd09badfa3943397d3af4a8eeaaa187283ce56661e59b42814`).
- Observado no código da interface: a seleção chama `transferPlayback` e um
  mesmo aparelho pode oferecer as modalidades `cast` e `connect` (evidência
  REA `ev_67a19d82ee85881ff5ab26ebc589d2921159ad40f21891a80f6c5d06cf924cd4`).
- Esta foi uma análise **estática da interface**. Não demonstra o protocolo
  nativo, a autenticação, a descoberta principal do Spotify Connect ou o
  transporte de áudio. O Pulse reproduz o fluxo de uso com componentes e
  protocolo próprios; Google Cast é uma integração separada.
