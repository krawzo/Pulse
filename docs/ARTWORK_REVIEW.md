# V2.4 — revisão de capas locais

## Escopo

- Ler somente imagens embutidas em tags ID3/APEv2 de MP3s locais. A leitura é sob demanda; a varredura textual da pasta continua sem carregar imagens.
- Exibir apenas `coverFront` que decodifique corretamente. Não buscar imagens na rede nem arquivos `cover.jpg`/`folder.jpg` ao lado do MP3. Sem capa válida, usar o placeholder Pulse.
- Para coleção/álbum, escolher a primeira faixa com capa válida na ordem título e caminho. Cada faixa no player usa sua própria capa.
- Não persistir bytes ou caminho de artwork no `AudioTrack` ou em `library.json`; não escrever em tags ou arquivos de áudio.

## Limites de memória e leitura

- Tags ID3/APEv2 maiores que 24 MiB são ignoradas antes da extração. MP3s longos continuam elegíveis se a tag estiver abaixo do limite.
- Decodificar proporcionalmente até 192 px no lado maior; `BoxFit.cover` faz o recorte central dentro do quadrado exibido.
- Cache LRU em memória de até 40 entradas e 4 MiB, futures deduplicadas e extrações seriais. A chave inclui path, tamanho e data de modificação.

## Revisão visual

- Alvos: linha 40–44 dp; mini-player 48 dp; dock 52 dp; shelf compacto 104 dp; card de coleção desktop ~128 dp; hero de álbum 112 dp compacto e 176 dp desktop.
- Capa e fallback mantêm o mesmo espaço. O fade curto começa depois do primeiro quadro decodificado.
- `test/goldens/pulse_artwork_home_{360,1280}x800.png` e `pulse_artwork_album_{360,1280}x800.png` usam uma capa sintética larga com faixas verde, azul e rosa e círculo laranja, para evidenciar recorte e centro.
- `test/goldens/pulse_track_artwork_{embedded_cover,missing_cover_fallback,corrupt_cover_fallback}_120x120.png` verificam capa, ausência e corrupção.

## Validação local

- `flutter analyze lib test`: sem issues.
- `flutter test`: 32 testes passaram; 48 goldens sintéticos.
- `flutter build windows --release`: aprovado em `build/windows/x64/runner/Release`.
- Não foi usada uma biblioteca pessoal. Não houve teste de janela Windows/DPI, leitor de tela ou saída de áudio físico.
