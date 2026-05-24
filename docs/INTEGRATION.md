# Como os dois repositórios convivem

Há DOIS repositórios separados, com papéis distintos. Eles NÃO devem ser mesclados.

## Repositório 1 — GameServer (terceiros / Camada A)
- Origem: https://github.com/marcusvrom/GameServer (fork da linhagem SixShoot→EddieJr→marcusvrom)
- Conteúdo: binários *Server, schema SQL, painel PHP original, install/server.
- Você NÃO desenvolve isto — apenas configura e opera. Tratar como artefato externo.
- Na VM, fica em: /root/gf_server

## Repositório 2 — gf-ops (seu / Camada B) = ESTE scaffold
- Conteúdo: CLAUDE.md, docs, scripts (create_account.sh, boot), painel reescrito, patches.
- É o SEU trabalho autoral, versionado e evoluído por você (+ Claude Code).
- Referencia o GameServer, mas vive separado.

## Como organizar na prática (escolha UMA)

### Opção A — Repos independentes (RECOMENDADA para agora)
Mais simples. Os dois lado a lado; seus scripts operam sobre /root/gf_server.
```
git clone https://github.com/marcusvrom/GameServer /root/gf_server
git clone <seu-gf-ops> /root/gf-ops
# scripts em gf-ops assumem BASE=/root/gf_server
```
- Prós: simples, sem fricção de submódulo.
- Contras: sem trava automática de versão dos server files (controle manual).

### Opção B — Git submodule (quando crescer)
gf-ops referencia GameServer num commit fixo, para rastreabilidade total.
```
cd gf-ops
git submodule add https://github.com/marcusvrom/GameServer vendor/gameserver
git submodule update --init --recursive   # em clones futuros
```
- Prós: trava de versão explícita; sabe exatamente qual build está usando.
- Contras: clone precisa de --recursive; updates manuais.

## O que vai para CADA repo (regra de ouro)
- Mudou um binário, schema ou o painel ORIGINAL? → fica no GameServer (ou num fork seu dele).
- Escreveu script, doc, painel novo, patch, automação? → vai para o gf-ops.
- Em dúvida: "isso é artefato do jogo ou engenharia minha ao redor?" decide o repo.

## Fluxo de trabalho com Claude Code
- Aponte o Claude Code para o repo gf-ops (onde está o CLAUDE.md).
- O CLAUDE.md já documenta a Camada A como externa ("não desenvolvemos"),
  então o Claude Code sabe operar sobre /root/gf_server sem tentar reescrever binários.
