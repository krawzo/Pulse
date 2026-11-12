# Pulse desktop review r17 e r18

## r18 — implementação visual

Partimos da auditoria em `R18_VISUAL_AUDIT.md`. A versão r18 concentra navegação global em uma barra preta, transforma a lateral em navegador de biblioteca com miniaturas e filtros, usa carrosséis horizontais para álbuns e faixas e exibe hero contextual em álbuns/playlists. A fila abre no painel direito sem perder o estado de reprodução. O dock agora tem 88 px e controle de volume. Foram capturados estados de biblioteca, álbum, playlist, Agora tocando, fila, Configurações e Jellyfin nas resoluções 1280×800, 1440×900 e 1920×1080. A identidade Pulse e os dados reais da biblioteca permanecem.

## Histórico r17

Reference: [Spotify desktop redesign](https://newsroom.spotify.com/2023-06-20/spotify-desktop-experience-redesign-your-library-now-playing-views-customize/). The Pulse layout follows the three region pattern: library at left, browse and collections in the center, Now Playing at right, with transport at the bottom. The panels remain resizable. Pulse colors, icons, artwork placeholders and identity remain its own.

The new Jellyfin entry is visible in the library rail. Connection is found only under Settings. The remote catalog shows its origin on each track, with filters for playlists and artists. At 1280×800 and 1920×1080 the existing center and right panels remain readable; the r17 captures are in the review package. Mobile work is deferred.

The local catalog, queues, favorites, playlists, expanded player and palette behavior were kept as the base of this revision.
