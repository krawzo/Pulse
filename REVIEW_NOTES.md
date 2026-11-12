# Pulse Flutter — pacote de revisão V2.5

- Escopo: Configurações locais para biblioteca, reprodução, tema/densidade, cache temporário e informações do app; sem conta, rede, busca online ou escrita nos MP3s.
- Validação local final: `flutter analyze lib test` sem issues; `flutter test` 40/40; build Windows Release aprovada com versão/build lidos localmente do pubspec; 70 goldens conferidos.
- A suíte inicializou após regenerar snapshots impactados pelas cores de tema nos textos secundários; os quatro casos de retomada estão incluídos na aprovação 40/40.
- Conteúdo: saída Release portátil, documentação, spec e renders vetoriais de Design e 70 capturas sintéticas. Sem instalador ou assinatura.
- Artefato atual: `artifacts/Pulse-Flutter-Settings-Windows-Review-20261008-r2.zip`; SHA-256 registrado apenas no sidecar adjacente.
- Retomada persiste sessão/fila local e abre pausada; cache de capas continua em memória e pode ser regenerada.
- Limites: não houve teste com biblioteca pessoal, janela nativa/DPI, leitor de tela ou áudio físico.
- Júlia aprovou a revisão fiscal V2.5 com 93/100 para teste do usuário. Este é um pacote portátil de revisão, sem instalador/assinatura e sem cópia para a pasta oficial; não representa lançamento de produção.
