# Pulse Mobile com Navidrome — versão local em desenvolvimento

## O que foi integrado

- O Android oferece Jellyfin ou Navidrome no login e nas configurações.
- O Navidrome usa sua API OpenSubsonic para autenticação, catálogo, artistas,
  playlists, favoritos, letras, streaming, capas e downloads do arquivo original.
- A fila e a posição são salvas no Navidrome enquanto o Pulse reproduz uma fila
  composta apenas por faixas desse servidor. Num dispositivo sem retomada local,
  o Pulse tenta recuperar a fila salva na conta.
- Sessões, catálogo e downloads ficam separados por provedor e conta. A sessão
  Jellyfin já existente continua em sua chave segura original. A opção
  **Trocar servidor** preserva a sessão para uso posterior.
- O desktop continua oferecendo o fluxo Jellyfin atual. A camada de cliente
  musical agora tem uma interface comum, preparando o suporte desktop posterior.

## Teste local de 17/10/2026

O endereço `https://navidrome.discovery.dev.br` está ativo com TLS. O servidor
responde pela API OpenSubsonic e contém 377 faixas indexadas e uma conta. Um
APK de revisão separado, identificado como `com.example.pulse_flutter.preview`
e exibido como **Pulse 2.0 Teste**, foi compilado e instalado no emulador Android
15. Ele abriu sem falha fatal observada. A cópia para instalar no celular fica
em `C:\Users\Administrador\Discovery\Projetos\Pulse Mobile 2.0\Pulse-2.0-Navidrome-Teste.apk`.

Ainda não houve login com a conta real. Portanto, catálogo, capas, reprodução,
letras, playlists, favoritos, downloads e retomada entre dispositivos seguem
sem validação de ponta a ponta. O APK de teste não substitui a instalação atual
do Pulse no celular.

`flutter analyze lib test` apontou quatro avisos. A suíte `flutter test`
terminou com 40 testes aprovados e 28 falhas, concentradas em testes de tela
com elementos ausentes ou imagens diferentes das referências, além de um teste Jellyfin que ainda espera
a rota antiga `/universal` para áudio enquanto o cliente usa `/stream`. Esses
resultados não demonstram falha de autenticação Navidrome, mas impedem afirmar
que a suíte esteja aprovada.

Antes de publicar, conferir em um Android: login, número de faixas, capas,
busca, reprodução, letras sincronizadas, playlist vazia e com músicas,
favoritos, download offline e recuperação da fila em outro dispositivo.
Também verificar o limite de tamanho da fila salva no servidor. A troca de
controle em tempo real continua sendo responsabilidade do Pulse Connect;
`savePlayQueue` do OpenSubsonic guarda estado, mas não controla outro aparelho.

## Próxima etapa

Validar a integração com a conta Navidrome no celular. Só então adaptar o
fluxo de conexão do desktop e planejar a migração de playlists/favoritos.
