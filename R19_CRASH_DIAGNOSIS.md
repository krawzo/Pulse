# Pulse Flutter r19 — estabilidade Windows

## Falha relatada

Após abrir a r18 em outro computador, o usuário maximizou a janela, que parou de responder e fechou. Eventos WER Application 1000/1001 de 12/10/2026, cerca de 00:06–00:07 (São Paulo), indicaram `pulse_flutter.exe` 0.3.0.18, exceção inicial `0xc0000005` em `flutter_windows.dll+0x3c1ca`, seguida de `0xc000041d`. O EXE executado correspondeu ao SHA-256 da r18 (`AA41C5B0338961DB112E8295ABF35F149479784CA878605E177619A570D18624`). O DLL executado correspondeu ao DLL Release do Flutter 3.47.6 usado no build (`53238C00BED3FB6E0D822EB18F18DCAC093BB30D4502DBFE78B9057690B18699`). Não havia minidump da sessão afetada.

O PDB desse mesmo engine, com `llvm-symbolizer --relative-address`, mapeou `0x3c1ca` para `ui::AXNode::id` dentro de `flutter::AccessibilityBridge::CreateRemoveReparentedNodesUpdate`, `accessibility_bridge.cc:229`. Ali o engine lê `child->parent()->id()` após um `assert(child->parent())`; o assert não protege a build Release. Esse é o ponto nativo confirmado pela combinação WER, hash e PDB. A razão pela qual a árvore ficou inconsistente naquela sessão não está confirmada sem minidump.

O [issue Flutter #175041](https://github.com/flutter/flutter/issues/175041) registra falha na mesma função. Um relato posterior no mesmo issue descreve o crash ao enumerar UI Automation durante a inicialização e verificou `ExcludeSemantics` na raiz como mitigação. O [código do engine nessa revisão](https://github.com/flutter/flutter/blob/692136cb65/engine/src/flutter/shell/platform/common/accessibility_bridge.cc) mostra a leitura nativa. O layout e os plugins do Pulse não têm prova de serem a causa primária; mexer no runner para bloquear `WM_GETOBJECT` também falhou no caso reproduzido no issue.

## Mudança r19

`PulseWindowsAccessibilityBoundary` envolve o conteúdo do `MaterialApp` em `ExcludeSemantics` no Windows por padrão. Isso evita enviar a árvore de widgets ao bridge problemático. O argumento `--enable-windows-accessibility` remove o limite para quem precisa testar leitor de tela. O custo é claro: leitores de tela não conseguem navegar o Pulse no modo padrão da r19. Mouse, teclado, controles, dados locais e Jellyfin não foram alterados. É uma mitigação até existir correção comprovada do engine; não é reparo da causa dentro do Flutter.

## Verificação e limite

- Na máquina de desenvolvimento, a r18 original sobreviveu a 12 ciclos de maximizar/restaurar/redimensionar; com consulta UI Automation, sobreviveu a mais 20 ciclos.
- Com perfis isolados vazio e com 200 faixas sintéticas, a r18 original sobreviveu a três execuções por perfil com consulta UI Automation e maximização. O crash do outro computador **não foi reproduzido aqui**.
- A r19 inclui testes que confirmam o limite de semântica no Windows, o opt-in e o comportamento em outras plataformas.
- `tools/probe_windows_maximize.ps1` realiza maximização/restauração na janela Release e consulta UI Automation, com perfis isolados por padrão.
- `flutter analyze` terminou sem problemas; `flutter test` passou com 68 testes, sem regenerar capturas. `tools/build_windows.ps1` gerou Release 0.3.1+19. O EXE Release tem SHA-256 `F3252BE9C48710AFBA988D4173CF07E9B32CC4A219D6C54768D4C2BF7C51FC95`.
- Na r19 Release, o script completou 10 ciclos por perfil (vazio e 200 faixas) no modo padrão e 3 ciclos por perfil com o opt-in; em todos o processo sobreviveu. Isso testa mensagens reais de maximizar/restaurar e consulta UI Automation neste Windows, mas não reproduz a condição que derrubou a r18 em outro computador.
- O EXE já copiado para o pacote foi executado separadamente e sobreviveu a mais 5 ciclos por perfil; seu hash é idêntico ao Release compilado.
- A validação decisiva ainda é abrir a r19 no computador afetado e repetir o gesto. Se voltar a fechar, recolher WER e minidump antes de outro patch.

Este pacote não inclui nem modifica os dados em `%LOCALAPPDATA%\PulseFlutter`. A r18 e as versões anteriores permanecem disponíveis separadamente.
