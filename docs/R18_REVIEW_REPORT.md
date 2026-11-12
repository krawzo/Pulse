# Pulse Flutter r18 — revisão Windows

## Entrega

- `App/`: Release Windows completo. Execute `pulse_flutter.exe` dentro desta pasta, junto às DLLs e `data`.
- `Source/`: fonte Flutter portátil, projeto Windows, testes e goldens. SDK, cache, build anterior, sessão e credenciais não acompanham o pacote.
- `DesignReview/`: r17 antes em 1280×800 e 1920×1080; r18 depois em 1280×800, 1440×900 e 1920×1080 para biblioteca, álbum, playlist, Agora tocando, fila, Configurações e Jellyfin. As imagens usam catálogo sintético.
- `SHA256SUMS.txt`: hashes de arquivos principais para conferência.

## Comparação r17 → r18

| Região | r17 | r18 |
| --- | --- | --- |
| Topo | Busca e ações distribuídas na barra | Início circular, busca central em cápsula, histórico e ações discretas |
| Esquerda | Destinos em menu | Biblioteca com miniaturas, filtros, busca e ordenação; mantém itens também nas Configurações |
| Centro | Lista longa e atalhos pequenos | Atalhos compactos, prateleiras de capas e detalhes de álbum/playlist com capa, metadados e play circular |
| Direita | Apenas Agora tocando | Agora tocando ou fila no mesmo painel, mantendo redimensionamento |
| Dock | 104 px | 88 px, transporte central, tempo/progresso e volume funcional |

Flutter foi mantido: o redesenho usa os controladores, dados e runtime já existentes. As paletas alternativas continuam disponíveis. A paleta escura padrão usa superfícies neutras e verde vivo; no tema claro, o verde escuro preserva contraste. O Jellyfin permanece opcional em Configurações, com os mecanismos de sessão e proxy existentes.

## Verificação feita

- `flutter analyze`: sem problemas.
- `flutter test`: 65 testes passaram sem atualizar os goldens, incluindo API simulada, persistência, player e estados responsivos.
- `tools/build_windows.ps1`: Release Windows `0.3.0+18` gerado.
- 21 capturas r18 nas três resoluções solicitadas; biblioteca, álbum, playlist, Agora tocando, fila, Configurações e Jellyfin.
- A pasta r17 e outros pacotes anteriores foram mantidos.

## Limites da prova

As capturas e testes usam fixtures sintéticas. Não comprovam audição física, uma biblioteca pessoal extensa, login real no Jellyfin ou execução interativa no Windows de destino. O arquivo EXE não é assinado nem inclui instalador. O Visual C++ Redistributable pode ser necessário no computador de destino.

Referências visuais: [Spotify desktop redesign](https://newsroom.spotify.com/2023-06-20/spotify-desktop-experience-redesign-your-library-now-playing-views-customize/) e [Spotify PC/Mac FAQ](https://community.spotify.com/forum/en/kb/articles/929-faq-the-new-spotify-app-for-pc-and-mac). A interface usa a marca Pulse.
