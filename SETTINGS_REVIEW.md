# Pulse Flutter — revisão das Configurações V2.5

## Escopo

Configurações locais para pasta/análise da biblioteca, retomada pausada da sessão, avanço automático, tema claro/escuro, densidade dos controles, cache temporário de capas e informações do app. Não adiciona contas, rede, busca online, escrita nos MP3s ou migração do catálogo.

Preferências e sessão ficam separadas do catálogo em `%LOCALAPPDATA%\PulseFlutter\preferences.json`. A sessão reconcilia a faixa/fila com os IDs que ainda existem na biblioteca; não inicia áudio automaticamente. Uma fila alterada preserva as faixas que continuam disponíveis. Cache de artwork é só memória, até 40 miniaturas/4 MiB; limpar invalida leituras anteriores.

Na restauração, a fila mantém a ordem salva e omite IDs que não aparecem mais no catálogo; a faixa atual válida permanece na sessão.

## Capturas

`test/goldens/pulse_settings_*.png` cobre índice e seções Biblioteca, Reprodução, Aparência (escuro/claro), Armazenamento e Sobre em 360×800 e 1280×800. As imagens usam fixtures sintéticas; o teste também mantém o mini-player/nav compactos e o dock desktop.

## Verificação local

- `flutter analyze lib test`: sem issues.
- `flutter test`: 40/40 testes passaram após regenerar os goldens cujo texto secundário agora usa as cores do tema; inclui quatro testes focados de retomada. Foram conferidos 70 goldens em 360×800 e 1280×800.
- `flutter build windows --release` com `tools/build_windows.ps1`: aprovado; Sobre recebe versão/build do `pubspec.yaml` via metadados locais.
- As três densidades alteram linhas para 56/64/72 dp; os controles de favorito/menu têm área mínima de 48 dp. Tema claro inclui biblioteca vazia, mini-player, dock e tela Agora tocando.
- O pacote de revisão é portátil e não assinado. Não foi copiado para a pasta oficial nem testado contra uma biblioteca pessoal.
- Janela Windows/DPI, leitor de tela e reprodução física continuam fora da verificação automatizada.
- Júlia aprovou a revisão fiscal V2.5 com 93/100 para teste do usuário. É uma build portátil de revisão, sem instalador ou assinatura; não foi copiada para a pasta oficial e essa aprovação não declara lançamento de produção.
