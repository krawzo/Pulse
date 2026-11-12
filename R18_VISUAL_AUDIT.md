# Auditoria visual r17 → r18 (antes de editar)

Referência escolhida: [Spotify, redesenho Desktop de Your Library e Now Playing](https://newsroom.spotify.com/2023-06-20/spotify-desktop-experience-redesign-your-library-now-playing-views-customize/), complementada pela [FAQ oficial do aplicativo para PC/Mac, atualizada em setembro de 2026](https://community.spotify.com/forum/en/kb/articles/929-faq-the-new-spotify-app-for-pc-and-mac). A referência estabelece biblioteca ancorada à esquerda, centro de navegação, Agora tocando à direita, busca global e painéis ajustáveis. As capturas r17 comparadas estão no pacote r17, em `DesignReview/`.

## Diferenças observadas na r17

| Região | r17 | Alvo r18 |
| --- | --- | --- |
| Topo | Marca Pulse, voltar/avançar, busca larga e botão de adicionar pasta concorrem na mesma faixa | Barra preta de 64 px; Início circular ao lado da busca central em cápsula; ações discretas à direita. Marca Pulse permanece sem logo Spotify. |
| Biblioteca esquerda | Menu vertical de destinos ocupa a maior parte do painel; playlists são texto pequeno abaixo | Cabeçalho “Sua biblioteca” com criar/recolher; chips Faixas/Álbuns/Artistas/Playlists/Jellyfin; busca e ordenação próprias; itens com capa de verdade ou placeholder. |
| Cores/superfícies | Preto com base navy; centro e laterais azulados; cantos/bordas variáveis | #000000 no topo/dock/fundo, #121212 no centro/painéis, hover neutro #1f1f1f, verde no play; intervalo de 8 px e raio coerente. |
| Página inicial | “Acesso rápido” textual, cards pequenos e lista longa de faixas | Atalhos compactos em grade com capa e fileiras de capas; usa só álbuns, playlists e faixas existentes, sem recomendações inventadas. |
| Coleções | Álbum com cabeçalho funcional mas pouco contexto visual; playlist com título e controles isolados | Hero contextual com capa grande, título, metadados; faixa de ações com play circular verde; colunas e densidade de tabela. |
| Agora tocando | Painel preserva funcionalidade, mas r17 destaca controles em pílulas e não acompanha o ritmo do centro | Capa generosa, metadados compactos, fila acessível, recolhimento e redimensionamento preservados. |
| Dock | Capa à esquerda, controles grandes e progresso em uma segunda linha | 88 px pretos; metadados à esquerda, controles pequenos e tempo/progresso concentrados no centro, ações e volume à direita. |

## Decisão técnica

Continuar em Flutter. A base já oferece layout, mouse/foco, áudio, armazenamento local e conexão Jellyfin; a fidelidade desejada depende dos widgets e medidas, não de trocar o runtime. A r18 preserva as versões empacotadas e os dados em `%LOCALAPPDATA%\PulseFlutter`.
