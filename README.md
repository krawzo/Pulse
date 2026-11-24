# Pulse

Pulse é um reprodutor de música para Android e Windows, feito para ouvir e organizar uma biblioteca própria com controle sobre o servidor e os arquivos. O projeto reúne catálogo, busca, artistas, álbuns, playlists, fila, favoritos, letras e reprodução em uma interface para celular e computador.

A proposta é manter a experiência de ouvir música simples sem depender de um catálogo comercial. O Pulse pode usar músicas locais e conectar-se a um servidor pessoal. A integração com Navidrome/OpenSubsonic está em evolução; o projeto também contém suporte a Jellyfin. Alguns recursos dependem do servidor, do dispositivo e da versão instalada.

## Baixar

A versão oficial para **Windows é 0.3.63 (build 82)**. Para **Android, a versão oficial é 0.3.64 (build 83)**. Os arquivos prontos para instalar estão na pasta [executaveis](executaveis/):

- [APK oficial para Android 0.3.64](executaveis/Pulse-Mobile-Oficial-v0.3.64-build83.apk)
- [Instalador oficial para Windows 0.3.63](executaveis/Pulse-Desktop-Instalador-Oficial-v0.3.63-build82.exe)
- [Windows portátil oficial 0.3.63](executaveis/Pulse-Desktop-Portatil-Oficial-v0.3.63-build82.zip)

Eles também estão disponíveis na [release oficial v0.3.64-build83](https://github.com/krawzo/Pulse/releases/tag/v0.3.64-build83). No Android, abra o APK no celular. No Windows, execute o instalador EXE ou extraia o ZIP portátil e abra `pulse_flutter.exe`.

No Windows, a prévia na barra de tarefas oferece controles de favorito, faixa anterior, reproduzir/pausar e próxima faixa. Em Biblioteca > Tudo, músicas curtidas e playlists aparecem primeiro; o botão de ocultar a biblioteca foi removido. O cabeçalho da playlist acompanha a rolagem e dá lugar a uma barra compacta com capa, nome e reprodução.

As playlists conectadas mostram a capa fornecida pelo servidor, e Músicas curtidas tem uma capa própria. O Windows mantém uma sessão do Pulse por vez: abrir novamente traz a janela existente para frente. Ao atualizar pelo instalador, as instâncias abertas são encerradas antes da substituição dos arquivos e a nova versão abre ao final.

No Android, a biblioteca e os atalhos também exibem as capas das playlists do servidor. Músicas curtidas usa a capa roxa e azul com coração branco e mostra o nome da conta. Ao abrir uma playlist, sua capa aparece no topo quando o servidor a fornece.

## Código e documentação

O aplicativo é feito em Flutter. `lib/` contém a interface e a lógica compartilhada; `android/` e `windows/` contêm a integração de cada plataforma; `tools/` reúne os scripts de compilação. As notas de projeto, revisões e histórico anterior estão em [docs](docs/).

Para compilar, instale o Flutter compatível com o SDK Dart definido em `pubspec.yaml`, execute `flutter pub get` e use os scripts em `tools/` conforme a plataforma. O SDK do Flutter e arquivos gerados de compilação não fazem parte deste repositório.
