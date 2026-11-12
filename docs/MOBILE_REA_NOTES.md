# Pulse Mobile: referência Android e etapas

## Referência examinada em 13/10/2026

- Spotify Android `com.spotify.music` 9.1.90.2270 (versionCode 147078674), APK de 142.124.037 bytes obtido em [APKPure](https://apkpure.net/spotify-app/com.spotify.music/download). É a versão mais recente encontrada nos catálogos públicos consultados nesta data; distribuição por etapas pode oferecer outra versão a certos usuários.
- SHA-256 do arquivo: `5c05366de31788fd0eec6e046c3610311acf5e63c15345e5bdaca6e8f09fb3b4`. O valor também consta em [outra listagem pública](https://captain-droid.com/es/apps/audio/spotify-music/attachment/com-spotify-music_147078674-apk/).
- A assinatura do APK foi verificada localmente: SHA-1 do certificado `d6a6dced4a85f24204bf9505ccc1fce114cadb32`. A versão e o pacote foram conferidos com as ferramentas Android locais.
- REA `inspect_artifact`: `ev_7483ee16d4e799e8e984b7afc6e4f658884debda7f77c3c7b218888213aa3f6d`. REA `inspect_android_package`: `ev_bc30013943ed4d14ca6ac2c3f9b38718699c7843b0f9784afce7c61dfe38b514` (98.076 classes e 4.874 recursos identificados).

## Observações que orientam o Pulse

- O manifesto declara um serviço de biblioteca de mídia e outro de navegação de mídia; o primeiro usa `foregroundServiceType="mediaPlayback"`. Isto sustenta tratar reprodução em segundo plano, controles do sistema e Android Auto como um módulo próprio, separado da tela.
- A busca de classes REA encontrou `NowPlayingActivity`, `TrackSeekbarNowPlaying`, `TrackCarouselNowPlaying` e controles separados para anterior, próximo, fechar e menu (`ev_a5091ba5c093b41f116929fa66b9c6ebe6af2718ab9e70346b52f48ee52d0276`). São nomes e membros presentes no APK; não comprovam comportamento em execução.
- A busca também encontrou modelos para filtros e ordenação da biblioteca (`ev_c1cf59324cae5d987366e2c98f811060e6492ec3ad8cf36ee309a1060875c12f`). O Pulse usa esses conceitos com dados locais e Jellyfin, sem copiar código, recursos ou identidade visual do Spotify.

## Etapas do Pulse Mobile

1. **V1: encontrar e tocar.** A versão 0.3.5+23 substitui a lista desktop no mobile por Início com atalhos e álbuns, Busca de faixas/álbuns/artistas/playlists, Biblioteca com filtros e um Tocando agora em tela cheia com cor da capa. As ações usam os dados locais e Jellyfin do Pulse; não são recomendações nem catálogo do Spotify.
2. **V2: reprodução móvel.** A versão 0.3.4+22 adiciona a sessão de mídia Android ao mesmo controlador de áudio do Pulse, com estado da fila e comandos do sistema para reproduzir, pausar, avançar, voltar e buscar posição. A versão 0.3.6+24 adiciona uma fila mobile com toque para reproduzir, mover ou remover próximas faixas e timer; playlists, álbuns e curtidas mostram uma capa maior no Android. Ainda faltam prova em telefone com tela apagada, tratamento refinado de interrupções de áudio e reordenação por gesto de arrastar.
3. **V3: dispositivos.** Pulse Connect por etapas, começando com descoberta/painel e depois saída de áudio para outro Pulse e Google Cast. Tratar troca de dispositivo e falhas de rede sem perder a fila local.

## Implementado na 0.3.7+25

- O player mobile abre o painel Pulse Connect pela ação de dispositivos, usando a mesma descoberta e o mesmo controlador de saída do desktop. No Android, a busca mantém a recepção multicast do Wi-Fi ativa só durante a varredura. A saída para TV ainda depende de validação numa rede real.
- A biblioteca Android importa arquivos MP3 escolhidos no seletor do sistema para o armazenamento privado do Pulse. A cópia mantém os originais intactos e persiste após fechar o app; selecionar uma pasta inteira com sincronização automática ainda exige outra integração com o Storage Access Framework.
- O toque prolongado numa playlist da Biblioteca ou da Busca abre ações mobile de fila, edição, cópia para outra playlist, pasta, criação, compartilhamento e exclusão. Álbuns, artistas, curtidas e Jellyfin continuam usando o mesmo catálogo e os mesmos controladores do desktop.

## Implementado na 0.3.8+26

- Seleção de pasta inteira pelo Storage Access Framework do Android. O Pulse recebe permissão de leitura persistente, copia os MP3 e subpastas para o armazenamento privado e permite atualizar essa fonte depois. Os originais permanecem intactos. A seleção de arquivos individuais continua disponível.
- Menus de coleção em folha inferior no Android, incluindo as ações completas de playlist ao abrir seus detalhes; toque prolongado também funciona nos atalhos da tela inicial.
- Fila móvel com arrastar para reordenar as próximas faixas, além dos comandos já existentes de mover e remover.
- Timer no menu da faixa, organização visual por pastas na Biblioteca, degradê da capa do Jellyfin e navegação pelo botão Voltar do Android.
- Sessão de áudio Android com pedido de foco antes da reprodução local; o Pulse pausa em interrupções e ao desconectar fones. Não retoma automaticamente depois de uma chamada para evitar áudio inesperado.
- Configurações móveis deixam de mostrar inicialização e bandeja do Windows e explicam corretamente o armazenamento das cópias locais.

A APK 0.3.8 abriu no emulador, iniciou a reprodução da faixa sintética e importou uma pasta MP3 pelo seletor do Android. Depois de reiniciar o emulador sem apagar os dados, o arquivo copiado e a faixa continuaram visíveis. A análise estática do Flutter não encontrou problemas e a compilação Android terminou. Ao trocar de fonte, a última faixa da fonte antiga produz um aviso de retomada indisponível na abertura seguinte; a nova biblioteca continua acessível. A reordenação por gesto, interrupções de áudio, Jellyfin e Google Cast ainda não foram validados em telefone.

## Pulse Connect na 0.3.9+27

- O Pulse agora anuncia sua presença e procura outras instalações do Pulse por UDP na rede local. O painel separa aparelhos Pulse de TVs Google Cast e identifica computador ou celular. O anúncio contém apenas o nome do aparelho, a plataforma e um identificador temporário; não leva música, credenciais nem comandos de reprodução.
- A descoberta alcança Wi-Fi e cabo quando fazem parte da mesma rede local e o roteador não isola os clientes. Ela não atravessa a internet nem substitui a etapa futura de transferência de áudio entre Pulses.
- A compilação foi conferida, mas não houve teste entre celular e PC na mesma rede nesta rodada: os aparelhos do usuário estão em redes diferentes no momento.

## Limites da APK 0.3.7 distribuída

- A análise do APK foi estática. Ela não observa conta, experimentos de interface, regras do servidor ou áudio ao vivo.
- A importação local da APK seleciona arquivos MP3 e ocupa armazenamento privado do aplicativo; não há acompanhamento contínuo da pasta original nessa APK. A sessão de mídia foi compilada, mas a reprodução real em segundo plano e os controles da tela bloqueada não foram validados em telefone. O APK de revisão é uma build debug, não um instalador de loja.
- A APK 0.3.7 abriu no emulador Android, importou uma faixa sintética, iniciou a reprodução e preservou a faixa após reinstalação. Isso não valida Jellyfin, áudio com tela apagada ou Google Cast em aparelhos reais.
