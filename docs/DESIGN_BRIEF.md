# Pulse Flutter — briefing visual

**Direção:** player de música local/offline. Windows primeiro; Android depois. Preservar a identidade Pulse e adaptar o layout a cada plataforma. Este é um briefing de design para Programação, não autorização para alterar Pulse Electron, V1, V2 ou a pasta oficial.

**Atualização V2.3:** para a rodada atual, use os critérios em `artifacts/Pulse-Flutter-V2.3-Design-Proposal-20261008/PROPOSTA-VISUAL.md`; eles refinam a densidade e os breakpoints abaixo sem substituir escopo local/offline nem recovery.

## Etapa atual e evolução

- **Requisito desta etapa:** player Flutter Windows, biblioteca local/offline, leitura de MP3 para teste, favoritos/playlists e tema Pulse; sidebar, lista e dock de player. Nenhuma conta, rede ou servidor.
- **Android futuro:** layout adaptado para toque; seleção de pasta pelo SAF com URI e grant persistente guardados no adaptador Android; validar revogação, reinício e fonte movida.
- **Evolução Android:** reprodução em segundo plano/tela bloqueada com Media3 `MediaSessionService` e controles de sistema.
- **Fora desta etapa:** migrar dados/código do Electron, remover a V1/V2, Jellyfin ou metadados online. Preservar o projeto Flutter isolado; uma migração de biblioteca exige decisão e plano próprios.
## Identidade e tokens

Usar como base os tokens já presentes no shell Flutter:

| Token | Valor |
|---|---|
| Fundo | `#111513` |
| Superfície | `#1A211D` |
| Superfície elevada | `#202923` |
| Seleção | `#20382B` |
| Destaque Pulse | `#54D68B` |
| Texto principal | `#F1F5F2` |
| Texto secundário | `#A5B0A9` |
| Texto discreto | branco a 54% |
| Divisor | branco a 10% |

Manter o carvão, o verde, a tipografia e os ícones da marca. Erro e aviso precisam de texto/ícone além da cor. Conferir contraste antes de fechar as cores semânticas.

## Layout responsivo

Decidir pelo espaço real da janela, sem detectar o tipo de dispositivo.

| Largura | Navegação e conteúdo | Player |
|---|---|---|
| Compacta: `<600 dp` | Barra inferior com Biblioteca, Favoritos e Playlists; chips Faixas/Álbuns/Artistas; atalhos em duas colunas e shelf de álbuns rolável. | Mini-player acima da navegação; abre “Tocando agora” |
| Média: `600–719 dp` | Navigation rail com Biblioteca, Favoritos e Playlists. | Player compacto persistente |
| Média larga: `720–839 dp` | Sidebar de 196 dp quando sobram pelo menos 480 dp para conteúdo. | Player compacto persistente |
| Expandida: `≥840 dp` | Sidebar Pulse de 232 dp com Biblioteca, Faixas, Álbuns, Artistas, Favoritos e Playlists. | Dock inferior persistente |

No Windows, preservar densidade de lista, atalhos, foco de teclado e hover discreto. No Android, usar alvos de toque de pelo menos 48 dp, respeitar insets e gesto de voltar; não espremer a sidebar desktop no telefone.

## Componentes e telas

- **App shell/navegação adaptativa:** sidebar no desktop; rail ou barra inferior conforme largura.
- **Cabeçalho da biblioteca:** título, busca e ação contextual.
- **Linha de faixa:** capa/fallback, título, artista, metadados disponíveis, favorito e menu; indisponibilidade não depende só de cor.
- **Estado vazio:** “Sua biblioteca começa aqui”, explicação offline e ação “Adicionar pasta”/“Selecionar pasta”. Cancelar o seletor é neutro.
- **Status de biblioteca/importação:** vazio, verificando, lendo `X/Y` somente quando o total real for conhecido, concluído ou erro parcial. Exibir no conteúdo sem esconder navegação/player.
- **Player:** dock no Windows, com faixa/controles/progresso/fila; mini-player e tela “Tocando agora” no Android. Controles refletem o estado real. Não há volume nesta rodada porque o controller atual não o expõe.
- **Confirmação:** qualquer remoção do catálogo explica impacto em favoritos/playlists; nunca apaga ou move os arquivos de áudio.

## Contrato de estados para alinhar com Programação

Manter acesso à fonte, varredura e disponibilidade da faixa como estados separados; não reduzir tudo a `available`.

```text
LibraryState: empty | loading | ready | failed
ScanState: idle | enumerating | processing(done, total?) | complete | partialError
SourceAccess: notConfigured | permissionPending | granted | denied | disconnected
TrackSource: unknown | present | missingConfirmed | readError
Playback: idle | loading | playing | paused | error
```

- IDs de faixa, favoritos e playlists não mudam quando a pasta é reconectada.
- Só uma varredura completa e autorizada da mesma fonte pode marcar uma faixa como `missingConfirmed`. Erro parcial ou permissão negada preserva o estado anterior.
- Cancelar o seletor não é negação nem erro. Falha na importação preserva biblioteca, favoritos e playlists.
- **Android/SAF:** guardar URI concedida e grant persistente no adaptador nativo; não inventar API de permissão por caminho. O pacote [`file_selector`](https://pub.dev/packages/file_selector) oferecer seleção de diretório não comprova que o acesso persiste após reiniciar. Validar leitura da árvore SAF depois de reiniciar e tratar URI movida/revogada como recuperável. [Documentação SAF](https://developer.android.com/training/data-storage/shared/documents-files).
- **Player em segundo plano:** reprodução com tela bloqueada e controles do sistema é evolução Android separada, usando `MediaSessionService`/Media3; não é garantida por manter a tela Flutter ativa. [Documentação Media3](https://developer.android.com/media/media3/session/background-playback).

## Aceite visual

1. Windows a 1280 × 800 mantém sidebar, lista legível e dock sem sobreposição.
2. Abaixo de 840 dp, navegação e player compactam; abaixo de 600 dp, não há sidebar estreita.
3. Android a 360 × 800 mantém busca, mini-player e navegação utilizáveis, respeitando insets.
4. Estados vazio, importando, permissão negada, desconectada, erro parcial e player ativo têm mensagem e ação coerentes.
5. Biblioteca, favoritos, playlists e faixas acessíveis continuam utilizáveis sem internet; nenhuma integração Jellyfin/online entra nesta etapa.

**Referências:** [plataformas Flutter](https://docs.flutter.dev/reference/supported-platforms), [SAF Android](https://developer.android.com/training/data-storage/shared/documents-files), [reprodução em segundo plano Media3](https://developer.android.com/media/media3/session/background-playback), [layouts adaptáveis Android](https://developer.android.com/design/ui/mobile/guides/layout-and-content/adapt-layout).

