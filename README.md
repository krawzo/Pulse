# Pulse

Pulse é um reprodutor de música para Android e Windows, feito para ouvir e organizar uma biblioteca própria com controle sobre o servidor e os arquivos. O projeto reúne catálogo, busca, artistas, álbuns, playlists, fila, favoritos, letras e reprodução em uma interface para celular e computador.

A proposta é manter a experiência de ouvir música simples sem depender de um catálogo comercial. O Pulse pode usar músicas locais e conectar-se a um servidor pessoal. A integração com Navidrome/OpenSubsonic está em evolução; o projeto também contém suporte a Jellyfin. Alguns recursos dependem do servidor, do dispositivo e da versão instalada.

## Baixar

A versão publicada aqui é **0.3.54 (build 73), beta**. Os arquivos prontos para instalar estão na pasta [executaveis](executaveis/):

- [APK para Android](executaveis/Pulse-Mobile-Beta-v0.3.54-build73.apk)
- [Instalador para Windows](executaveis/Pulse-Desktop-Instalador-Beta-v0.3.54-build73.exe)

Eles também estão disponíveis na [release v0.3.54-build73](https://github.com/krawzo/Pulse/releases/tag/v0.3.54-build73). No Android, abra o APK no celular. No Windows, execute o instalador EXE.

## Código e documentação

O aplicativo é feito em Flutter. `lib/` contém a interface e a lógica compartilhada; `android/` e `windows/` contêm a integração de cada plataforma; `tools/` reúne os scripts de compilação. As notas de projeto, revisões e histórico anterior estão em [docs](docs/).

Para compilar, instale o Flutter compatível com o SDK Dart definido em `pubspec.yaml`, execute `flutter pub get` e use os scripts em `tools/` conforme a plataforma. O SDK do Flutter e arquivos gerados de compilação não fazem parte deste repositório.
