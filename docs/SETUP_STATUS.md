# Pulse Flutter — situação de setup e verificação

Atualizado em 2026-10-08 após a implementação V2.5 de Configurações locais para Windows.

## Estado atual — V2.5

- Configurações acessíveis pelo header compacto e pelo rodapé da sidebar desktop. No compacto/intermediário, índice e detalhe com retorno; desktop amplo mantém subnav interna e painel de coluna única.
- Preferências separadas do catálogo em `%LOCALAPPDATA%\PulseFlutter\preferences.json`: retomar faixa/posição/fila em pausa, manter a ordem da fila ao reconciliar IDs, avançar automaticamente, tema escuro/claro e densidade Compacto/Padrão/Confortável.
- Tema claro usa paleta de alto contraste; densidade padrão compacta preserva alvos de toque mínimos de 48 dp. Trocas de preferência são salvas imediatamente e revertidas com aviso se a escrita falhar.
- Biblioteca reutiliza seletor, confirmação e estados de reanálise já existentes. Cache de capas em memória informa limite de 4 MB e limpa sem confirmação; operações anteriores à limpeza não podem repovoar o LRU.
- Sobre informa Pulse, versão/build, armazenamento local e ausência de conta/busca online.
- 70 goldens sintéticos: 48 anteriores, 14 capturas das seções Configurações, 2 telas iniciais em tema claro e 6 estados de densidade em 360×800/1280×800. Não equivalem a janela nativa/DPI ou leitor de tela.

- Desktop: atalhos horizontais de Favoritos/playlists, shelf de álbuns separado, lista densa de faixas, busca com voltar/avançar e dock persistente.
- Compacto: busca, chips para Faixas/Álbuns/Artistas, atalhos em duas colunas, shelf horizontal, conteúdo rolável, mini-player e navegação inferior fixos.
- Tocar um álbum abre temporariamente suas faixas, agrupadas pelo par álbum+artista; nenhuma seleção nova é persistida.
- Player neutro sem faixa selecionada; duração/progresso só aparecem quando há sessão real de reprodução. Não há controle de volume exposto pelo controller atual.
- Paleta Pulse carvão/floresta; verde `#54D68B` para ação/seleção. Capa frontal ID3 é lida do MP3 sob demanda; faltas e erros mantêm o placeholder. Sem rede, sem escrita em áudio e sem bytes de artwork no JSON.
- A coleção escolhe a primeira capa frontal válida por título+path. O shelf compacto usa 104 dp, mini-player 48 dp, dock 52 dp, card desktop ~128 dp e hero do álbum 112/176 dp. A cache LRU guarda até 40 entradas/4 MiB; thumbnails preservam proporção e têm no máximo 192 px no lado maior. Tags ID3/APEv2 acima de 24 MiB são ignoradas; o comprimento do MP3 não limita a leitura de uma tag menor.
- Fonte local, favoritos, playlists e recovery seguem sem migração; `AudioTrack`, IDs e o formato de persistência não mudaram.
- Histórico V2.4: analyze sem issues, 32 testes, 48 goldens e Release aprovado; pacote de artwork r2 preservado.
- V2.5: `flutter analyze lib test` sem issues; `flutter test` 40/40 após atualização dos goldens de textos secundários; `flutter build windows --release` aprovado pelo script local que injeta versão/build a partir do `pubspec.yaml`; 70 goldens sintéticos conferidos.
- Pacote de Configurações V2.5: `artifacts/Pulse-Flutter-Settings-Windows-Review-20261008-r2.zip`; SHA-256 no sidecar adjacente. Gate fiscal aprovado por Júlia com 93/100 para teste do usuário. Build portátil de revisão, sem instalador/assinatura; nenhuma cópia foi feita para a pasta oficial.
- Fixtures são sintéticas. Nenhuma biblioteca pessoal foi aberta. Não foi feito teste de áudio físico, janela nativa/DPI ou leitor de tela.

## Ambiente

- Flutter 3.47.6 / Dart 3.13.5 instalado localmente em `tools/flutter`.
- Windows Desktop, Visual Studio C++ Build Tools e dependências Pub configurados no workspace.
- Este workspace não é um repositório Git.
- Scaffolds Android existem, mas Android SDK/ADB, SAF persistente e playback em segundo plano não estão validados. Não fazem parte desta rodada.

## Capacidades atuais

- Varredura recursiva local de MP3 e leitura de tags ID3 existentes para título, artista e álbum. Título do arquivo é fallback; tags ausentes não são inventadas.
- Persistência do caminho escolhido, catálogo, favoritos, playlists e data da leitura em `%LOCALAPPDATA%\PulseFlutter\library.json`, com gravação por arquivo temporário/backup.
- Busca por metadados e playlists, reprodução/fila/seek local e interface responsiva conforme `DESIGN_BRIEF.md`.
- `sourceState` representa a fonte persistida e `scanAttemptState/scanAttemptPath` a tentativa atual. Reconectar tenta diretamente a raiz salva; escolher outra pasta usa o seletor. Progresso de uma raiz nova identifica o alvo e mantém a fonte/catálogo anteriores visíveis. Falha parcial não remove faixas por inferência; reconexão atualiza o catálogo apenas após leitura completa.
- Escolher uma pasta diferente pede confirmação antes de substituir a fonte em exibição.

## Verificação histórica V2.0

- `flutter analyze lib test`: aprovado, sem issues.
- `flutter test`: 17 testes auto-descobertos passaram. Os arquivos `library_search_test.dart` e `windows_library_persistence_test.dart` foram executados separadamente por caminho, acrescentando 2 + 5 casos. Total único: 24 testes aprovados.
- `pulse_home_page_responsive_test.dart`: 7 testes aprovados em execução direcionada. 16 goldens cobrem oito estados (fonte configurada vazia, desconectada, reconectando, lendo pasta nova, erro de leitura, parcial, reconectada e falha parcial em pasta nova) em 360 dp e 1280 dp; mais dois goldens cobrem biblioteca sem fonte e dois busca sem resultados.
- `flutter build windows --release`: aprovado em 20,6 s. Executável: `build/windows/x64/runner/Release/pulse_flutter.exe`.
- Persistência validada com armazenamento temporário e MP3s sintéticos: reinício, pasta escolhida, favoritos, playlists, indisponibilidade, reconexão e preservação do último snapshot em falha parcial.
- Nenhuma biblioteca pessoal foi aberta ou percorrida. O áudio foi confirmado pelo usuário numa build anterior; esta build não foi testada com biblioteca pessoal nem auditada por audição física.
- Pacote de revisão: `artifacts/Pulse-Flutter-V2.0-Windows-Review-20261008-r3.zip` (pacote da saída Windows para revisão, sem instalador). SHA-256 do ZIP r3: `3B855F307422B38077F958CF9D20ECAC3DD2FB690B6992F79BC3DDCEA3426956`.

## Como executar no Windows

Na raiz do projeto, com Windows Desktop e C++ Build Tools disponíveis:

```powershell
.\tools\flutter\bin\flutter.bat pub get
.\tools\flutter\bin\flutter.bat run -d windows
.\tools\flutter\bin\flutter.bat analyze lib test
.\tools\flutter\bin\flutter.bat test
.\tools\build_windows.ps1
```

A saída Release fica em `build\windows\x64\runner\Release\`. O ZIP de revisão contém essa saída e material de revisão; não é instalador.

## Limitações e escopo futuro

- O pacote Windows não é instalador assinado; VC++ Redistributable não está incluído e pode ser requisito no destino.
- Ícone/nome legal e metadados de empresa ainda têm valores provisórios; assinatura e instalador estão fora do escopo.
- Android requer SDK/dispositivo, adaptador SAF com permissões persistentes e validação de reprodução em segundo plano.
- Jellyfin permanece integração futura separada da pasta local. Sem Android, Jellyfin, fontes externas de artwork ou instalador nesta rodada.
- O arquivo de áudio sintético testa o caminho de leitura e fallback; não comprova decodificação ou saída de som real.











## Parecer de Design

- Reavaliação r3 concluída por Marina em 2026-10-08: **94/100**, acima do gate de 90; nenhum defeito visual concreto no escopo foi encontrado.
- O parecer revisou os 20 goldens sintéticos e o código atual, mas não reexecutou analyze/test/build nem validou independentemente o SHA do ZIP.
- Limitações visuais: os PNGs são renderizações Flutter sintéticas, não captura de janela nativa em DPI real. Hover, foco/teclado e áudio físico não foram verificados.
- O parecer de Design não substitui a aprovação fiscal de Júlia para liberação da V2.0.
