# Pulse coordination

## Project and scope
- Programming Work: `C:\Users\Administrador\Downloads\Codex\Pulse-Flutter` (Flutter foundation for the offline music player).
- Do not modify Pulse V1/V2 Electron or the official folder `C:\Users\Administrador\Discovery\Projetos\Pulse - Reprodutor` from this Work.
- Júlia — Coordenação Fiscal: task `01a11258-b779-70f2-801a-98f7c7af8bf2`.

## Collaboration protocol
1. At the end of every task, post a textual final response in this Work with a summary, changed files, checks performed, and limitations.
2. Exchange criteria and reviews with the existing Design Work, task `01a1174f-ca92-7ff0-b3a5-cf65b2c64ea9`, through Codex when available. Record relevant decisions here when useful.
3. If a direct message asks for approval and work cannot continue under the current policy, record the request and current assessment here, notify the coordinator, and continue any independent work; do not remain idle.
4. Do not ask the user for approval to send internal work messages.

## Initial handshake
- 2026-10-08: Sent Design a one-line handshake through Codex asking for receipt and future exchange of criteria/reviews. the send was accepted, and Design confirmed receipt. Design also reported successfully messaging Programming through Codex; direct communication worked both ways.

## Design handshake and current review criteria
- 2026-10-08: Design confirmed receipt through Codex and will share reviews/artifacts for joint work.
- Review against `DESIGN_BRIEF.md`: charcoal base and Pulse green `#54D68B`; compact layout below 600 dp, rail from 600–839 dp, sidebar/dock at 840 dp and above; in compact layout, mini-player above navigation; search and empty states must communicate scope; error states need text and icon.
- Latest visual round: goldens passed above 90/100 after green harmonization and removal of a duplicate CTA. Remaining detail noted: folder icon in “Limpar busca”.


## Pessoas e responsabilidades
- Programação Flutter: Rafael Costa (persona de trabalho; não representa contratação de uma pessoa).
- Design de Produto: Marina Alves (persona de trabalho).
- Júlia — Coordenação Fiscal: task `01a11258-b779-70f2-801a-98f7c7af8bf2`.
- Work Design: task `01a1174f-ca92-7ff0-b3a5-cf65b2c64ea9`.

## Histórico transferido do Work anterior
- Esta pasta é a fonte de trabalho Flutter e não é um repositório Git. O histórico registra Flutter 3.47.6/Dart 3.13.5 em `tools/flutter`, dependências Pub resolvidas e Windows Desktop C++ Build Tools configurado. Android SDK/ADB ainda não estava instalado.
- Player local/offline para Windows: `file_selector`, `audio_metadata_reader` e `audioplayers`; varredura recursiva de MP3; leitura de tags ID3 existentes sem inventar metadados; catálogo JSON em `%LOCALAPPDATA%\PulseFlutter`; favoritos, playlists, busca por metadados, fila, seek e controles de reprodução.
- Interface responsiva: bottom navigation abaixo de 600 dp, rail entre 600–839 dp e sidebar/dock a partir de 840 dp; player compacto e folha “Tocando agora”; dock na tela expandida.
- Histórico de ajustes: busca sem resultados, destaque Pulse `#54D68B`, remoção de CTA duplicada no overview e estados “PLAYER PRONTO”/“REPRODUZINDO”/“PAUSADO”.
- Aceite do usuário: a música tocou na biblioteca real na build testada. Isso é relato do usuário, não validação de áudio realizada por este Work.
- Parecer de Design: goldens atualizados avaliados em 92/100, acima do gate 90; verde coerente e CTA duplicada removida. Pendência visual: trocar o ícone de pasta com sinal de mais do botão “Limpar busca” por ícone de limpar/fechar.
- Última verificação fiscal transferida: `flutter analyze lib test` sem issues; 10 testes passaram; `flutter build windows --release` passou; executável abriu e respondeu com título Pulse. São resultados históricos, não reexecutados neste turno.
- Artefato histórico: `artifacts/Pulse-Windows-Player-Status-Review.zip`; conferir conteúdo e atualidade antes de reutilizar.
- Limitações conhecidas: entrega é pasta/ZIP portátil de revisão, sem instalador assinado; VC++ redistributable não está empacotado; nome/ícone legal/company têm placeholders. `README.md` e `SETUP_STATUS.md` estão desatualizados e devem ser atualizados na próxima rodada de implementação/build.
- Android exige adaptador SAF com permissões persistentes e playback em segundo plano; aguardar SDK/dispositivo e escopo. Jellyfin é integração futura separada da fonte local. Não iniciar Android/Jellyfin nem migração sem autorização e escopo.
- Offline/local é prioridade. Não abrir nem varrer a biblioteca pessoal sem pedido explícito.

## Fluxo de revisão conjunta
- Para futuras implementações que afetem UI/UX, Programação enviará a Marina um pedido de revisão de Design pelo Codex.
- Ao concluir a revisão, Design responderá no thread com achados e notas. Programação registrará decisões relevantes aqui.
- Programação sempre publicará resposta final textual neste Work ao concluir uma tarefa, com resumo, arquivos, verificações e limitações.
- 2026-10-08: Marina confirmou pelo Codex: Programação solicita revisão quando a mudança afetar UI/UX; Design publica achados, evidências/limitações e nota no Work de Design, sem implementar código durante a revisão; Programação registra decisões relevantes e publica o relatório final da execução no Work de Programação.



## V2.0 — critérios Design recebidos (2026-10-08)
- “Limpar busca”: botão de campo apenas quando há consulta, ícone close/limpar, tooltip e rótulo acessível; manter foco ao limpar. Estado sem resultados inclui consulta e instrução; CTA usa ícone de busca/limpar, nunca pasta. Todas as ações limpam a mesma consulta sem trocar dados ou fonte.
- Distinguir fonte ainda não configurada de pasta configurada indisponível. Quando desconectada, identificar a fonte e oferecer reconectar/escolher pasta; manter último catálogo válido, sinalizado possivelmente desatualizado. Cancelar seletor é neutro; permissão/erro de leitura devem ser nomeados separadamente de fonte ausente.
- Durante reconexão, manter player/navegação/catálogo disponíveis e progresso indeterminado, sem inventar contagens. Atualizar catálogo apenas após leitura completa. Sucesso comunica reconexão sem modal.
- Falha parcial tem estado próprio com ícone, texto e nova tentativa; manter último catálogo válido e não inferir remoções ou contagens. Ao escolher outra pasta explicitamente, sinalizar troca de fonte.
- Revisão final pedida em goldens compacto e expandido para: vazio sem fonte, desconectada com catálogo preservado, reconectando, erro parcial, reconectada com sucesso e busca sem resultados. Design revisará diff/goldens e retornará evidências, limitações e nota no Work Design sem implementar código.

## V2.0 Windows local/offline — implementação e validação (2026-10-08)
- Aplicados os critérios de Marina: botão de campo “Limpar busca” com close e tooltip; CTAs de busca sem resultado usam ícone de busca/limpar; limpar mantém o campo e a tela de origem. Há confirmação ao selecionar outra pasta.
- A store percorre a árvore explicitamente e só aceita o resultado se a leitura completa terminar. Falha da fonte, erro de leitura ou falha parcial não substitui o último snapshot. Reabrir o app verifica se a pasta salva ainda existe; ao reconectar a mesma pasta, leitura completa salva o catálogo novo e mantém favoritos/playlists.
- `WindowsLibraryStore` aceita diretório de dados injetado para testes; o app continua usando `%LOCALAPPDATA%\PulseFlutter`. Fixtures e persistência rodam apenas em temporários com arquivos sintéticos.
- Estados registrados e goldens compacto/expandido: sem fonte (goldens existentes), desconectada, reconectando, erro de leitura, parcial, reconectada e busca sem resultados. Goldens novos de recuperação ficam em `test/goldens/pulse_source_*`.
- Arquivos de implementação: `lib/data/windows_library_store.dart`, `lib/state/library_controller.dart`, `lib/ui/pulse_home_page.dart`. Testes atualizados em `test/windows_library_persistence_test.dart` e `test/pulse_home_page_responsive_test.dart`; documentação em `README.md` e `SETUP_STATUS.md`.
- Verificação final: `flutter analyze lib test` sem issues; 19 testes únicos passaram (14 auto-descobertos, mais 2 de busca e 3 de persistência executados por caminho); suíte responsiva de 6 casos também passou com goldens atualizados; `flutter build windows --release` passou em 20,3 s.
- Artefato produzido após as verificações: `artifacts/Pulse-Flutter-V2.0-Windows-Review-20261008.zip`. É pacote de revisão da saída Release, sem instalador; não inclui VC++ Redistributable nem assinatura.
- Nenhuma biblioteca pessoal foi aberta ou percorrida. Os testes de persistência usam diretórios temporários; teste físico de áudio não foi executado nesta build. O aceite de áudio citado no histórico é do usuário numa build anterior.
- Revisão visual final enviada a Marina pelo Codex; nota/parecer ainda pendente. Coordenação fiscal: Júlia, task `01a11258-b779-70f2-801a-98f7c7af8bf2`.

## Parecer Design — rodada inicial V2.0 e correção solicitada (2026-10-08)
- Marina devolveu nota provisória 89/100: os goldens visuais passaram qualitativamente em 360/1280 dp (ícone de busca, banners, catálogo/favoritos/playlists, mini-player/nav e dock), mas pediu correção de dois fluxos antes de superar 90.
- Achado 1: reconectar a mesma pasta, agora acessível mas sem MP3, deixava `sourceState` como desconectada e escondia o aviso de pasta vazia. Correção: o controller passa a separar `sourceState` (fonte persistida) de `scanAttemptState`/`scanAttemptPath`; resultado vazio marca a fonte salva como acessível, preservando catálogo e exibindo mensagem da tentativa.
- Achado 2: uma leitura parcial ao tentar outra pasta enquanto a antiga estava desconectada deixava apenas o estado anterior e não identificava o alvo. Correção: registrar alvo/resultado da tentativa, preservar o status da fonte que ainda está salva e mostrar aviso específico do novo alvo junto ao banner da fonte antiga. A UI sempre exibe mensagem de tentativa quando existente.
- Acrescentados testes de controlador para pasta reaberta acessível sem MP3 e falha parcial ao selecionar pasta nova com fonte anterior desconectada; goldens para ambos os fluxos em 360/1280 dp.
- Aguardando nova rodada de análise, testes, build e parecer de Design; a nota 89/100 não constitui aprovação da V2.0.

## V2.0 após parecer e correção (2026-10-08)
- Marina avaliou a primeira entrega em 89/100. Os goldens foram considerados visualmente bons, mas a revisão identificou dois fluxos sem evidência: pasta reconectada acessível sem MP3 permanecia marcada desconectada; falha parcial ao escolher pasta nova não identificava a tentativa quando a fonte salva antiga estava desconectada.
- Corrigido no controller: estado da fonte persistida separado do estado/caminho da última tentativa. Pasta acessível sem MP3 deixa de ser indicada como desconectada; a biblioteca anterior permanece e a mensagem de resultado é exibida. Falha parcial em novo alvo preserva a fonte antiga e exibe o nome da pasta tentada, sem ocultar a mensagem sob o banner antigo.
- Testes adicionados para ambos os fluxos, além dos cenários já existentes de reinício, favoritos/playlists, desconexão, reconexão bem-sucedida e parcial na mesma fonte. Goldens novos mostram pasta vazia acessível e falha parcial ao escolher fonte nova, em 360/1280 dp.
- Revalidação após correção: `flutter analyze lib test` sem issues; 23 testes únicos aprovados (16 padrão + 2 busca + 5 persistência); suíte responsiva de 6 casos passou; `flutter build windows --release` passou em 20,7 s.
- Novo pacote: `artifacts/Pulse-Flutter-V2.0-Windows-Review-20261008-r2.zip`, contendo Release, documentação e 18 goldens sintéticos. Solicitada nova nota/parecer à Marina; fiscalização final de Júlia segue pendente.

## Parecer Design — reavaliação r2 (2026-10-08)
- Marina atribuiu nota 90/100. Confirmou que os dois fluxos do parecer anterior foram corrigidos e que as imagens continuam coerentes; 90 ainda não ultrapassa o gate de aprovação.
- Novo ponto 1: as ações do banner “Reconectar pasta” e de escolher outra fonte abriam o mesmo seletor. Correção aplicada: banner tenta diretamente a raiz salva; cabeçalho/overview continuam abrindo seletor com rótulo explícito “Escolher outra pasta”.
- Novo ponto 2: ao varrer fonte nova enquanto a antiga está desconectada, o banner usava o nome da raiz salva e dizia “Reconectando”. Correção aplicada: UI compara `scanAttemptPath` com a raiz salva e mostra “Reconectando pasta” para a mesma raiz ou “Lendo nova pasta” com os nomes do alvo e da fonte preservada para raiz diferente; progresso também exibe o alvo.
- Incluído teste de widget que prova que “Reconectar pasta” chama a raiz salva enquanto “Escolher outra pasta” permanece uma ação diferente; adicionados goldens de varredura de pasta nova em 360/1280 dp.
- Goldens são renders sintéticos Flutter, não captura nativa de DPI; nenhuma evidência cobre hover/foco/teclado ou áudio físico. Solicitada nova revisão após validação e pacote r3.

## Parecer Design — correções do r2 implementadas (2026-10-08)
- “Reconectar pasta” chama `addFolder` com `snapshot.rootPath` salvo; “Escolher outra pasta” continua no seletor e tem rótulo claro no cabeçalho/overview. Teste de widget confirma que reconectar usa a raiz salva.
- Progresso inclui nome da tentativa. Com `scanAttemptPath` igual à raiz salva, o banner diz “Reconectando pasta”; com alvo diferente, diz “Lendo nova pasta” e identifica a fonte/catalogo preservados. Goldens para alvo novo em 360/1280 dp.
- Revalidação atual: `flutter analyze lib test` sem issues; 24 testes únicos aprovados (17 padrão, 2 busca, 5 persistência); 7 testes responsivos aprovados; `flutter build windows --release` passou em 20,6 s.
- Pacote r3 criado e enviado a Marina para nota final; retorno de Design e aprovação fiscal de Júlia permanecem pendentes.


## Parecer final Design — r3 (2026-10-08)
- Marina avaliou o código e os 20 goldens sintéticos em 360/1280 dp e atribuiu **94/100**, acima do gate de 90. Não encontrou defeito visual concreto nos estados solicitados.
- Confirmou os dois fluxos do parecer 90: leitura nova identifica “Nova biblioteca” enquanto “Music”/catálogo permanecem disponíveis; reconectar usa a raiz salva e escolher outra pasta abre seletor distinto. Confirmou também pasta acessível sem MP3, falha de leitura/parcial, pesquisa e ícones coerentes.
- Evidências do parecer: 20 renders Flutter em `test/goldens`, controller/UI com separação `sourceState` e `scanAttemptPath`, teste de UI da chamada direta à raiz salva, testes de persistência das falhas e goldens de leitura nova.
- Limitações do Design: renders sintéticos, sem captura de janela nativa em DPI real; hover/foco/teclado e áudio não foram verificados. Marina não reexecutou analyze, testes ou build e não validou independentemente o SHA do ZIP; esses itens constam como nossas verificações locais.
- Status no fechamento do parecer Design: visual aprovado acima de 90; a decisão fiscal ainda aguardava Júlia e foi registrada como aprovada na seção seguinte.

## Gate fiscal V2.0 — aprovado (2026-10-08)
- Júlia aprovou a V2.0 após parecer final de Design 94/100 (>90), `flutter analyze lib test` sem issues, 24 testes únicos aprovados (17 auto-descobertos + 2 busca + 5 persistência) e `flutter build windows --release` aprovado.
- V2.0 está aprovada no gate fiscal. A aprovação não muda as limitações registradas: o ZIP é pacote de revisão, não instalador; build sem assinatura/VC++ Redistributable; sem teste de áudio físico nesta build.

## Proposta anterior de V2.1 — substituída pelo foco local/offline escolhido pelo usuário
**Objetivo:** fechar as lacunas de validação em janela nativa e distribuição Windows, mantendo o escopo local/offline.

**Escopo proposto:**
- Validar a Release em janela Windows nativa nos tamanhos/escala DPI disponíveis e revisar foco, teclado, hover, overflow e legibilidade dos estados de pasta, busca e player.
- Executar smoke test de reprodução, pausa, seek, fila, pasta desconectada e reconexão com uma pasta de teste dedicada e MP3 de teste autorizado; sem percorrer biblioteca pessoal.
- Validar o pacote em perfil/ambiente Windows limpo e documentar o pré-requisito do Visual C++ Redistributable e recuperação de dados/configuração.
- Registrar resultados, evidências e limitações; gerar novo pacote de revisão após analyze/test/build aprovados.

**Critérios de aceite propostos:**
- Nenhum overflow ou controle cortado nas escalas/tamanhos verificados; foco e rótulos acessíveis funcionam nas ações primárias por teclado.
- Playback, pause, seek e fila completam o fluxo de teste; estados desconectado/reconectado preservam os dados e atualizam após leitura completa.
- Pacote abre no ambiente limpo com pré-requisitos documentados; análise, testes e build passam e o hash do pacote é registrado.
- Nenhum instalador assinado ou publicação nesta V2.1 sem escopo e decisão separados sobre identidade do produto, publisher e assinatura.

**Status:** substituída. O usuário definiu V2.1 como melhoria da experiência local/offline; a proposta abaixo está em avaliação.


## Avaliação V2.1 — candidato a incremento local (aguardando decisão)
- Avaliação da persistência atual: `WindowsLibraryStore.load()` só restaura `.bak` se `library.json` estiver ausente. Se o arquivo primário existir mas estiver corrompido, o decode falha e `LibraryController.load()` mantém o snapshot inicial vazio e mostra erro. `save()` apaga o `.bak` depois de cada commit bem-sucedido, então não há cópia persistente anterior para recuperação normal.

### Proposta: recuperação não destrutiva do catálogo local
**Escopo candidato:** manter uma cópia da última versão conhecida como válida; validar `library.json` antes de aceitar; se o primário faltar ou estiver corrompido, recuperar cópia válida sem apagar o arquivo danificado; exibir estado não modal de recuperação; se primário e cópia estiverem inválidos, preservar ambos e informar que a recuperação falhou sem zerar/sobrescrever os arquivos.

**Critérios de aceite candidatos:**
- Saves sucessivos mantêm uma cópia anterior válida e não substituem os dados correntes por JSON inválido.
- Com primário corrompido e backup válido, o app restaura catálogo, favoritos, playlists e caminho; o arquivo danificado permanece preservado para diagnóstico e o usuário vê aviso de recuperação.
- Com primário ausente e backup válido, restauração segura também funciona.
- Com primário e backup inválidos, ambos permanecem intactos e a UI apresenta erro claro e uma ação de tentar novamente/abrir localização de dados; nenhum snapshot vazio é salvo por cima.
- Testes usam diretório temporário e fixtures sintéticas para cenários primário válido, backup, corrupção e falha de recuperação.
- Sem Jellyfin, Android, migração de dados ou biblioteca pessoal. Mudança de armazenamento precisa preservar compatibilidade do JSON existente.

**Decisão:** Júlia aprovou o incremento e os critérios fiscais em 2026-10-08. Marina respondeu com critérios específicos de UI: recuperação sem modal, estado de falha distinto de catálogo vazio, ação de retry, detalhes/cópia dos caminhos e preservação do primário corrompido como arquivo irmão. A revisão também apontou que troca de raiz pode órfãnar favoritos/playlists devido aos IDs baseados em caminho; isso é um risco separado, fora do P2 aprovado.

### Implementação V2.1 — recuperação local
- `WindowsLibraryStore.load()` valida o primário e o backup. Backup válido é usado e restaura o primário por promoção de temporário; se o primário estava corrompido, seus bytes ficam em `library.json.corrupt` (sufixo numerado se já existir). Primário/backup inválidos continuam intocados.
- Saves mantêm uma cópia anterior validada e arquivam backups inválidos antes de rotação. Falhas não apagam a única cópia válida; promoção usa arquivo temporário e rollback do primário.
- `LibraryController` impede mutações até um catálogo ser carregado e bloqueia escritas quando a leitura falha. A UI distingue falha de catálogo de biblioteca vazia, permite tentar novamente e mostra caminhos copiáveis; recuperação usa aviso informativo separado do estado da pasta de áudio.
- Testes sintéticos cobrem recuperação por backup, primário inválido, ambos inválidos sem escrita, criação de primário ausente e preservação de dados nas rotinas existentes. Compatibilidade do JSON mantida.
- Validação final: `flutter analyze` sem issues; `flutter test` aprovado; `flutter build windows --release` aprovado em 21,0 s. Os novos estados de sucesso/falha passaram checks responsivos de widget em 360 e 1280 dp; nenhum golden dedicado foi gerado para estes estados.
- Pacote de revisão preparado: `artifacts/Pulse-Flutter-V2.1-Windows-Review-20261008-r1.zip`; hash atualizado após a correção fiscal e inclusão dos quatro goldens dedicados (ver adendo abaixo).
- Revisão visual final solicitada à Marina; gate fiscal de Júlia informado, aguardando o parecer visual antes da decisão final.
- Ajuste após revisão fiscal da Júlia: `_rotateBackupFrom()` agora substitui o `.bak` válido anterior via staging/rollback, sem arquivar snapshots válidos `.previous*`; um backup inválido é preservado como `.corrupt`. Testes verificam oito saves sem crescimento de arquivos, validade do backup rotativo e preservação do backup inválido.
- Copy da confirmação de troca de pasta revisada para não prometer associação automática de favoritos/playlists por IDs baseados em caminho.
- Adicionados quatro goldens dedicados de recuperação concluída e bloqueada em 360×800 e 1280×800. Júlia pediu nova rodada visual após estas evidências e a correção da rotação.
- Pacote r1 substituído com a nova Release, documentação e quatro goldens. Analyze, suíte completa e Release build passaram após esta correção; Marina recebeu os quatro caminhos de imagem para nova revisão.
- Parecer final da Marina após avaliar a r1 atual e os quatro renders dedicados: **94/100 — aprovado**. A observação anterior sobre ausência de capturas foi substituída; Marina conferiu o hash `4E320C5D88832F1D4DD74D925A364858CE085F282489DEF7CD20012BF95CCE70`.
- Limites do parecer: renders sintéticos, sem janela Windows real, escala/DPI ou leitor de tela; Marina não reexecutou testes. Analyze, suíte completa e Release build foram validados localmente após a correção.

## V2.2 — direção visual “Sua coleção em foco”
- Referência de design: mockups e critérios de Marina em `artifacts/Pulse-Flutter-V2.2-Design-Concept-20261008`; não copia marca, ícones proprietários ou textos de Spotify. Layout responsivo: compacto <600 dp; rail 600–719; sidebar adaptativa a partir de 720 se preserva 480 dp de conteúdo; sidebar/dock >=840.
- Implementação visual: home de biblioteca com coleções locais e faixas, cards com arte abstrata determinística local, lista de faixas densa com título/artista, sidebar com playlists, player dock com controles/progresso centralizados e mini-player com arte. Busca, playback, favoritos, playlist, navegação, desconexão e recovery continuam usando os mesmos controllers/store.
- Componentes extraídos para `pulse_header.dart`, `pulse_navigation.dart`, `pulse_navigation_widgets.dart`, `pulse_collection_card.dart`, `pulse_local_artwork.dart`, `pulse_track_row.dart` e `pulse_player_dock.dart`; `pulse_home_page.dart` permanece responsável por coordenar estado e callbacks.
- Limites de dados respeitados: sem histórico de reprodução ou data de inclusão por faixa, então o título é “Faixas da biblioteca” (sem “Adicionados recentemente”); o modelo não fornece duração de faixa nem artwork, portanto arte é explicitamente abstrata e duração não é inventada. Sem rede, serviços remotos ou novos dados pessoais.
- Goldens sintéticos adicionados/atualizados em 360, 599, 600, 719, 720, 839, 840 e 1280 dp, com biblioteca vazia/povoada, faixa ativa, playlist aberta, busca e recovery bloqueado. Teste de widget confirma playlist aberta conserva o player nos dois layouts principais.
- Validação local após a implementação: `flutter analyze` sem issues; `flutter test` completo aprovado; `flutter build windows --release` aprovado em 21,2 s. Pareceres finais: Marina 93/100 (visual aprovado) e Júlia 92/100 (fiscal acima do gate). O pacote r2 mantém o registro da revisão.

## V2.3 — densidade e hierarquia da biblioteca (2026-10-08)

- Direção autoral de Marina: referência ampla de hierarquia/densidade de player musical, mantendo identidade Pulse. Sem logo/copy/ícones de terceiros, conta, rede, artwork real, histórico ou metadados inventados.
- Desktop ≥840: sidebar de 232 dp, busca com voltar/avançar, atalhos curtos de Favoritos/playlists, shelf horizontal de álbuns, lista mais densa e dock de três zonas. O dock não ganhou controle de volume porque o controller atual não expõe esse recurso.
- Compacto <600: busca, chips apenas para destinos reais Faixas/Álbuns/Artistas, atalhos em duas colunas com alvos de 68 dp e shelf horizontal de álbuns; conteúdo rola acima do mini-player e da navegação inferior fixos.
- Tocar álbum abre detalhe temporário filtrado por álbum+artista; voltar retorna à lista sem ID persistido. Playlists abertas mostram nome/contagem e retornam à lista. Player sem faixa fica neutro e sem barra/tempo.
- Médio preserva os cortes atuais: rail 600–719, sidebar adaptativa 720–839 quando restam 480 dp de conteúdo; sidebar desktop a partir de 840. Back/forward só aparece no layout desktop.
- Mudanças limitadas à apresentação e ao histórico temporário de navegação: `pulse_home_page.dart`, `pulse_header.dart`, `pulse_library_shortcut.dart`, `pulse_player_dock.dart`, `compact_mini_player.dart`, `pulse_theme.dart`. Nenhum controller, modelo, ID, store ou persistência foi alterado.
- Testes de widget adicionados para atalhos/hit targets, truncamento acessível, álbum homônimo separado por artista e navegação voltar/avançar. Goldens novos para álbum aberto em 360×800/1280×800; todos os estados V2.2 e cortes 599/600, 719/720, 839/840 foram regenerados/validados com fixtures sintéticas. Total: 41 PNGs.
- Validação final após correções visuais: `flutter analyze` sem issues; `flutter test` — 25 testes passaram; `flutter build windows --release` aprovado em 20,8 s. Renders são Flutter sintéticos, não validação de janela Windows/DPI, leitor de tela ou áudio físico. Sem acesso à biblioteca pessoal e sem cópia para pasta oficial.
- Parecer visual inicial da Marina no r1: 88/100, abaixo do gate, com dois bloqueios concretos. Correção 1: header sem ações de mutação durante recovery bloqueado; “Adicionar pasta” e “Nova playlist” somem, preservando retry/detalhes. Correção 2: shelf compacto usa atalhos de 48 dp para expor ao menos uma linha de faixa em 360×800 antes do mini-player. Teste responsivo confirma o limite da primeira linha e os botões ausentes no recovery; goldens compact-home e recovery foram atualizados.
- Pacote r2: `artifacts/Pulse-Flutter-V2.3-Windows-Review-20261008-r2.zip`; r1 e seu SHA permanecem preservados. O checksum r2 é publicado no arquivo `.zip.sha256` adjacente para evitar referência circular.
- Gate visual final de Marina no r2: **93/100 — aprovado**. Conferiu os dois bloqueios corrigidos, o checksum/sidecar, 41 goldens e correspondência 41/41 com `test/goldens`.
- Gate fiscal final de Júlia: **92/100 — aprovado acima do gate**. `flutter analyze`, 25 testes e build Release aprovados. V2.3 está liberada para teste do usuário; continuam fora da evidência janela nativa/DPI, leitor de tela e áudio físico.

## V2.4 — capas frontais ID3 locais (2026-10-08)

- `audio_metadata_reader` 1.8.0 suporta APIC e `PictureType.coverFront`. A extração ocorre sob demanda numa isolate; a varredura da biblioteca continua com `getImage: false`. A capa só aparece após decodificação válida; ausência e erro mantêm o placeholder existente.
- A seleção de álbum usa a primeira faixa com `coverFront` válido numa ordem estável por título e caminho. Outros tipos APIC, fotos de artista e arquivos de imagem ao lado dos MP3 não são substitutos. O modelo `AudioTrack` e `library.json` não mudaram.
- Proteção de recursos: tags ID3/APEv2 acima de 24 MiB são ignoradas, sem limite baseado no tamanho do MP3; miniaturas preservam proporção e têm lado máximo de 192 px; cache LRU de até 40 entradas/4 MiB, com leitura serial e futures deduplicadas.
- Direção visual de Marina aplicada após parecer r1 (88/100): shelf compacto 104 dp; mini-player 48 dp; dock 52 dp; linha 40–44 dp; card desktop ~128 dp; hero de álbum 112 dp compacto/176 dp desktop. A troca usa fade curto após o primeiro quadro decodificado. Os fixtures visuais usam uma imagem sintética larga com três áreas de cor para verificar recorte central.
- Goldens adicionais: home e detalhe de álbum com capa em 360×800/1280×800, mais componente em 120×120 para capa, ausência e corrupção. Total: 48 goldens. A captura sintética não substitui janela Windows/DPI, leitor de tela ou áudio físico.
- Validação após correção visual: `flutter analyze lib test` sem issues; `flutter test` 32/32; `flutter build windows --release` aprovado. O r1 é preservado; r2 inclui os tamanhos corrigidos, fixture colorida e goldens finais, com SHA-256 no sidecar. A reavaliação visual final de Marina ainda está pendente.

## V2.5 — Configurações locais (2026-10-08)

- Direção visual alinhada com Marina: gear no header compacto; Configurações separadas no rodapé da sidebar desktop; índice/detalhe no compacto e intermediário; subnav de 190 dp e painel limitado a 720 dp no desktop amplo. A tela preserva mini-player, navegação e dock.
- Implementados Biblioteca, Reprodução, Aparência, Armazenamento e Sobre. A pasta usa seletor/diálogo/`LibraryController` existentes. Retomada persiste faixa, posição e IDs de fila reconciliáveis e restaura em pausa. Avanço automático desligado para no fim da faixa sem apagar a fila.
- Tema claro segue a paleta de Marina; controles Compacto/Padrão/Confortável respeitam linhas de 56/64/72 dp e o padrão Compacto. Preferências ficam em arquivo separado do catálogo. A limpeza imediata atua apenas no LRU em memória de 4 MiB e protege contra repovoamento tardio.
- Capturas sintéticas para índice e cinco seções em 360×800/1280×800; Playback e Aparência nos dois temas. Teste da seção verifica navegação, visibilidade do player/dock, persistência do seletor, tema e snackbar de limpeza.
- Ajuste final após leitura de Marina dos renders: busca da biblioteca fica oculta durante Configurações para liberar espaço; subnav exibe “Armazenamento” por inteiro. As capturas foram regeneradas após o ajuste.
- Revisão técnica de Marina identificou a ordem da fila na retomada. A reconciliação agora percorre os IDs salvos em sequência, mantém a faixa atual válida e ignora só IDs ausentes. Analyze, suíte 35/35 e build Release foram repetidos após a correção.
- No primeiro envio de V2.5, Marina aprovou o alinhamento para implementação; Julia ainda precisava executar o gate fiscal.
- O pacote V2.5 é independente e não substitui o artwork r2. É uma build para teste do usuário; não foi copiada para a pasta oficial.

### Ajustes solicitados pela revisão fiscal (2026-10-08)

- Júlia inicialmente atribuiu 86/100 e bloqueou a rodada por densidade sem efeito real nas linhas, tema claro incompleto no player, versão/build fixos no Sobre e controles espremidos em Aparência. Também pediu alvos de toque de ao menos 48 dp.
- Foram aplicados: linhas 56/64/72 dp; favorito/menu em 48×48 dp mantendo artwork compacto; cores do tema para mini-player, dock, estados vazios e Agora tocando; rótulo e controles de Aparência empilhados abaixo de 840 dp; versão/build derivados de `pubspec.yaml` em `tools/build_windows.ps1`.
- A captura clara mostrou também a descrição de biblioteca vazia com contraste insuficiente; o texto agora usa a cor de superfície do tema.
- Validação final: `flutter analyze lib test` sem issues; `flutter test` 40/40; build Windows Release aprovada; 70 goldens sintéticos. Júlia aprovou a revisão fiscal com 93/100 para teste do usuário. O pacote continua sendo uma build portátil de revisão, sem instalador/assinatura e sem cópia para a pasta oficial.
- Correção de reconciliação da fila: faixa atual só é inserida se não estiver já na fila reconstruída, evitando duplicação com `queueIds` vazio. Quatro testes focados cobrem ordem salva, IDs ausentes, fila vazia sem duplicação e faixa atual isolada. Após regenerar os goldens dos textos secundários no tema claro/escuro, a suíte completa passou 40/40; analyze e build também passaram no código final. Parecer fiscal final: 93/100, aprovado para teste do usuário.

