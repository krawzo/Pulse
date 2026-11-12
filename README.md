# Pulse Flutter

## Pulse 0.3.30

Os avisos temporários do topo, inclusive o aviso de última faixa indisponível, desaparecem após 8 segundos. Se o Jellyfin recusar a criação de playlist com HTTP 401, o Pulse oferece **Reconectar**, abre o login sem precisar sair antes e tenta salvar a mesma playlist depois que a conta for autenticada. Caso o servidor continue recusando a operação, o aviso permanece claro; a atualização não altera permissões do Jellyfin.

## Pulse 0.3.29

A barra de espaço volta a inserir espaços nos campos de busca e outros campos de texto. Quando nenhum campo de texto está em uso, ela continua controlando pausa e reprodução.

## Pulse 0.3.28

Playlists criadas com músicas do Jellyfin passam a ser gravadas na conta do servidor. A mesma conta no celular e no PC vê essas playlists e as faixas associadas. O Pulse atualiza a lista ao voltar para o aplicativo e periodicamente enquanto ele está aberto. Músicas locais continuam em playlists locais; a sincronização requer conexão ao Jellyfin e não envia arquivos de áudio.

## Pulse 0.3.27

A tela de letras lê a tag LYRICS embutida nos arquivos Opus. Quando ela contém tempos LRC, os versos acompanham a música e permitem avançar ao tocar em uma linha. A leitura não modifica o áudio original.

## Pulse 0.3.26

A biblioteca local agora reconhece MP3 e Opus ao selecionar uma pasta no Windows ou Android. No Android, o seletor de arquivos individuais também aceita Opus. A leitura continua preservando o catálogo anterior se a pasta escolhida não contiver áudio compatível.

## Pulse 0.3.25

Depois de entrar na conta Jellyfin, as faixas aparecem diretamente na biblioteca principal, com álbuns, artistas, busca e favoritos. As playlists do servidor aparecem junto das demais playlists, sem um atalho separado para Jellyfin. Em novas instalações, os arquivos locais ficam ocultos até a pessoa adicioná-los ou ativá-los nas Configurações; uma preferência local já salva é preservada.

## Pulse Desktop 0.3.24

Corrige os ícones das miniaturas sem capa na barra lateral da biblioteca. Cada miniatura mostra um único símbolo centralizado, sem sobrepor a inicial do item.

## Pulse Mobile 0.3.23

A tela Tocando agora começa 15 px mais abaixo em relação à versão 0.3.22 para afastar o cabeçalho da câmera frontal.

## Pulse Mobile 0.3.22

O ícone Android agora usa a marca original centralizada em uma camada adaptável com fundo transparente. O desenho final e eventual preenchimento atrás da marca dependem do launcher do aparelho. A versão para Windows não muda nesta atualização.

## Pulse 0.3.21

Na tela de letras, **Sincronia** adianta ou atrasa a letra em passos de 0,5 segundo, até 5 segundos em cada direção. O ajuste fica salvo neste aparelho para cada faixa e também vale ao tocar um verso para avançar a música. **Restaurar** volta ao tempo original. O download do Jellyfin agora guarda a letra que o servidor disponibiliza separadamente do áudio; ela continua visível sem internet e é removida junto com o download. Faixas já baixadas antes desta versão precisam ser baixadas novamente para guardar essa letra separada.

## Pulse Connect 0.3.17

Corrige a descoberta de dispositivos Pulse: a porta do receptor agora continua anunciada depois que a descoberta inicia. Antes, PC e celular se encontravam, mas o painel mostrava “Atualize o Pulse neste aparelho” e desativava a conexão. O celular passa a aparecer como “celular Android” em vez de “localhost”. Atualize os dois aparelhos para esta versão.

## Pulse 0.3.16

O menu de cada faixa oferece **Tocar a seguir** para colocá-la imediatamente depois da faixa atual. Faixas do Jellyfin também oferecem **Baixar** e **Remover download**. O áudio e a capa baixados ficam no armazenamento do aplicativo, separados por servidor e conta Jellyfin; a faixa continua no catálogo e toca neste aparelho sem internet depois de reiniciar o Pulse. Cada aparelho precisa fazer seu próprio download. O painel **Fila** do desktop permite arrastar as próximas faixas para mudar a ordem, como no celular.

A revisão Android build 35 corrige a versão mostrada em **Configurações > Sobre**. O pacote anterior já tinha a versão Android 0.3.16, mas a tela exibia valores antigos fixos. Para novas compilações Android, use `tools/build_android.ps1`, que passa a versão do `pubspec.yaml` para a interface.

## Pulse Connect 0.3.15

Os dois aparelhos precisam estar atualizados para esta versão, abertos na mesma rede local e conectados ao mesmo servidor e usuário Jellyfin. A descoberta mostra apenas outros Pulse com essa identidade de conta. A primeira conexão pede confirmação no receptor; as próximas usam uma autorização guardada no armazenamento protegido do aparelho. Ao inverter a saída entre celular e PC, o Pulse transfere a faixa e a posição. Para músicas do Jellyfin, o receptor abre sua própria cópia da música e da capa. O avatar usa a imagem da conta Jellyfin quando ela existe.

Google Cast não aparece no painel nesta etapa porque uma TV Cast não fornece uma conta Jellyfin que o Pulse possa conferir. O filtro da descoberta serve para encontrar aparelhos; a confirmação inicial é necessária porque a identificação enviada na rede local não é uma prova criptográfica da sessão Jellyfin.

## Pulse Connect 0.3.12

A descoberta de outros Pulse agora inicia sem esperar o receptor de áudio abrir sua porta. Ao abrir o painel no Android, o aplicativo primeiro obtém o acesso à descoberta na rede Wi-Fi e depois procura os dispositivos. Para usar a transferência entre aparelhos, atualize **celular e computador** para esta versão e feche versões antigas do Pulse que ainda estejam abertas.

## APK Android de revisão

Para instalar no telefone, gere o APK com os três processadores suportados:

```powershell
.\tools\flutter\bin\flutter.bat build apk --debug --target-platform android-arm,android-arm64,android-x64
```

Confira se o APK contém `libflutter.so` nas pastas `lib/armeabi-v7a`, `lib/arm64-v8a` e `lib/x86_64` antes de distribuí-lo. A build 0.3.1+19 foi gerada para o emulador x86_64; embora incluísse bibliotecas de áudio ARM, faltava o motor Flutter para telefones ARM e o aplicativo fechava ao abrir. As builds a partir de 0.3.2+20 incluem as três arquiteturas. Instale a atualização sobre a anterior, sem limpar cache ou dados. O plano de evolução do Android e as observações da análise de referência estão em `MOBILE_REA_NOTES.md`.

## Estabilidade Windows r19

A r19 mitiga uma falha nativa de acessibilidade do Flutter observada ao abrir/maximizar a r18 em outro computador. No Windows, a árvore para leitores de tela fica temporariamente desativada por padrão; mouse, teclado e interface visual continuam ativos. Quem precisa validar um leitor de tela pode iniciar `pulse_flutter.exe --enable-windows-accessibility`, sabendo que isso reativa o caminho do engine associado ao crash. A análise, as provas e os limites estão em `R19_CRASH_DIAGNOSIS.md`. Esta revisão não altera biblioteca, preferências, sessão Jellyfin nem o layout r18.

## Revisão desktop r18

Esta versão mantém Flutter e traz a biblioteca visual com capas, filtros e busca própria; Início e busca no topo; álbuns e playlists com capa grande e cor contextual; fila no painel direito; e dock de 88 px com volume. O centro usa somente o catálogo local ou Jellyfin já carregado, sem gerar recomendações fictícias. A opção Jellyfin continua nas Configurações. Capturas em 1280×800, 1440×900 e 1920×1080, comparativos com r17 e limites de verificação estão no pacote de revisão.

Pulse Flutter abre direto na biblioteca, sem exigir login. O avatar da conta fica visível no topo do desktop e do Android; ao tocá-lo, a pessoa pode informar domínio HTTPS do servidor Jellyfin, usuário e senha. Não há cadastro de contas no Pulse. As músicas locais continuam independentes do servidor e respeitam a opção **Mostrar arquivos locais** nas Configurações.

## O que funciona

- Seleção e leitura recursiva de arquivos MP3 e Opus em uma pasta local.
- Leitura de título, artista e álbum quando existem tags ID3; sem preencher metadados ausentes com suposições. O nome do arquivo serve como título alternativo.
- Catálogo JSON, pasta escolhida, favoritos e playlists persistidos em `%LOCALAPPDATA%\PulseFlutter\library.json`.
- Busca por título, artista, álbum e playlists; fila local, controles de reprodução, avanço e busca por posição.
- Interface responsiva: navegação inferior abaixo de 600 dp, rail entre 600–719 dp, sidebar adaptativa de 720–839 dp quando restam 480 dp para conteúdo e sidebar/dock a partir de 840 dp.
- Início da biblioteca com atalhos compactos para favoritos/playlists, shelf horizontal de álbuns e linhas reproduzíveis; tocar um álbum abre o grupo filtrado por álbum e artista.
- No compacto, filtros em chips navegam apenas por Faixas, Álbuns e Artistas. No desktop, voltar/avançar acompanha destinos e detalhes abertos.
- Capas frontais ID3 válidas são lidas do próprio MP3 sob demanda e exibidas como miniaturas quadradas; sem capa frontal ou em caso de erro, o placeholder abstrato Pulse permanece. Coleções de álbum usam a primeira capa frontal válida em ordem estável. Os arquivos locais não são modificados. As linhas não inventam duração. O player sem faixa atual não mostra progresso.
- Estados separados para fonte salva e tentativa de leitura. “Reconectar pasta” tenta diretamente o caminho salvo; “Escolher outra pasta” abre o seletor. Falhas preservam o último catálogo válido; a tentativa de pasta nova e seu progresso são identificados sem confundir com a fonte salva.
- Confirmar explicitamente antes de trocar a fonte por outra pasta.
- Configurações: reanalisar/trocar pasta, retomar a sessão em pausa, controlar avanço automático, escolher tema e densidade, limpar cache de capas e consultar versão/privacidade.
- Preferências separadas em `%LOCALAPPDATA%\PulseFlutter\preferences.json`.
- Jellyfin: conexão HTTPS pelo avatar da conta ou nas Configurações por usuário/senha; Quick Connect permanece nas Configurações. Catálogo de áudio, artistas, playlists, favoritos e reprodução usam a sessão existente. O token fica em `%LOCALAPPDATA%\PulseFlutter\jellyfin-session.dpapi`, criptografado para a conta Windows com DPAPI. Capas e áudio usam um proxy restrito ao loopback, que envia a autorização ao servidor sem colocar o token na URL de mídia.

## Windows: usar e gerar build

Requer Flutter SDK, Windows Desktop habilitado e Visual Studio com a carga de trabalho de C++ para desktop. O SDK deste workspace está em `tools/flutter`; o pacote portátil de fonte omite o SDK e usa `flutter` no PATH.

No PowerShell, a partir da raiz do projeto:

```powershell
.\tools\flutter\bin\flutter.bat pub get
.\tools\flutter\bin\flutter.bat run -d windows
.\tools\build_windows.ps1
```

A saída Release fica em `build\windows\x64\runner\Release\`. O script lê nome e número da versão de `pubspec.yaml` e os incorpora localmente, sem consulta online; use-o para que a seção Sobre mostre os metadados da build. Para verificar código e testes:

```powershell
.\tools\flutter\bin\flutter.bat analyze lib test
.\tools\flutter\bin\flutter.bat test
```

## Testar a biblioteca sem usar sua coleção pessoal

Os testes automatizados criam arquivos de áudio sintéticos e dados de catálogo dentro de diretórios temporários, incluindo reinício do controlador, pasta indisponível, reconexão, leitura parcial, favoritos e playlists. Eles não abrem nem percorrem uma coleção pessoal e não verificam som físico.

Para verificar o fluxo manualmente, use uma pasta de teste com MP3s sintéticos/de revisão. Desconecte ou renomeie essa pasta, abra o Pulse e confirme que o catálogo salvo continua visível; “Reconectar pasta” tenta diretamente o caminho salvo. Use “Escolher outra pasta” para abrir o seletor. Se uma pasta nova estiver sendo lida, a tela identifica o alvo enquanto mantém o catálogo anterior visível. Um novo caminho pede confirmação antes da troca.

## Limitações

- O painel Pulse Connect procura instalações do Pulse na mesma rede local e TVs Google Cast. Ao escolher outro Pulse, o aparelho de destino pede autorização; a faixa atual é enviada por uma URL temporária restrita ao IP aprovado e os comandos de pausa, busca, volume e mudança de faixa continuam no aparelho de origem. O outro Pulse precisa estar aberto e atualizado; redes de visitantes e bloqueios de firewall podem impedir a descoberta ou a transferência. Esta etapa não sincroniza bibliotecas e filas entre contas nem permite assumir uma faixa que já estava tocando no aparelho de destino.

- A extração ignora tags ID3/APEv2 acima de 24 MiB para manter a leitura delimitada. MP3s longos continuam elegíveis quando suas tags ficam abaixo desse limite. A miniatura tem no máximo 192 px por lado e o cache local mantém até 40 entradas/4 MiB; a política não altera o catálogo persistido.
- A integração Jellyfin precisa de rede e de uma conta válida no servidor. A biblioteca local continua disponível offline. O Android tem Início, Busca, Biblioteca filtrada, Tocando agora, fila com controles, importação de MP3 e Opus pelo seletor de arquivos, painel Pulse Connect e uma sessão de mídia para controles do sistema. A reprodução com tela apagada, a descoberta de TVs e a importação em um telefone real ainda precisam de validação.
- A build desta rodada é uma saída Windows Release para revisão, sem instalador assinado. O Visual C++ Redistributable não está incluído e pode ser necessário no computador de destino.
- Nome/ícone legal e metadados de empresa ainda têm valores provisórios; assinatura e formato de instalador não estão definidos.
- Os testes e goldens usam fixtures sintéticas. A build desta rodada não foi autenticada com uma conta real, nem auditada por audição física.

## Design e revisão

`DESIGN_BRIEF.md` define os tokens e breakpoints visuais. `PULSE_COORDINATION.md` registra decisões e o fluxo de revisão com Design.
`SETTINGS_REVIEW.md` registra o escopo e as capturas de Configurações V2.5.

