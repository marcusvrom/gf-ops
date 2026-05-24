# Handoff para o Claude Code

Este arquivo te diz como passar o bastão desta fase de planejamento para o Claude Code
colocar a mão na massa. NÃO é preciso copiar nenhuma conversa — todo o contexto já vive
no `CLAUDE.md` e em `docs/`.

## Passo 1 — Pré-requisitos
- Conta Claude paga (Pro/Max/Team) ou Console — o Claude Code não roda no plano grátis.
- Instalar o Claude Code (instalador nativo, sem Node.js): ver docs.claude.com/claude-code.
- Rodar no Windows, WSL ou direto na VM Ubuntu. Recomendado: na própria VM (ou via SSH),
  onde ele tem acesso a /root/gf_server e pode testar de verdade.

## Passo 2 — Subir este repo (gf-ops) para o GitHub
```bash
# dentro da pasta gf-mvp/ (já é um repo git com histórico)
git remote add origin <url-do-seu-repo-gf-ops>
git push -u origin master
```
Mantenha o GameServer (os arquivos do jogo) num repo SEPARADO. Ver docs/INTEGRATION.md.

## Passo 3 — Abrir o Claude Code apontando para gf-ops
```bash
cd gf-ops          # a pasta com o CLAUDE.md
claude             # inicia a sessão; ele lê o CLAUDE.md automaticamente
```

## Passo 4 — Primeiro prompt (cole algo assim)
> Leia o CLAUDE.md e docs/server-files-notes.md por completo. Este é um servidor
> privado de Grand Fantasia com o MVP já validado. Confirme que você entendeu as 4
> invariantes críticas da seção 6 e o backlog da seção 8. Vamos começar pelo item 1
> do backlog: os systemd units. O servidor roda na VM em /root/gf_server; os achados
> de execução (locale C, libs i386, nscd, ordem de boot causal) estão documentados.
> Antes de escrever, me mostre seu plano para os 6 services + o target.

## Por que isso funciona
- O `CLAUDE.md` é lido no início de toda sessão → o contexto desta conversa já está nele.
- As invariantes (id==idnum, MD5, locale/i386/nscd, ordem de boot) impedem o Claude Code
  de regredir em coisas que descobrimos na marra.
- O backlog (§8) dá a fila de trabalho priorizada.
- A regra de ouro: a cada avanço, o Claude Code atualiza a tabela de estado (§5) e as notes.

## Mantendo o contexto vivo (importante)
- Sempre que algo mudar no mundo real (IP, versão, decisão), peça ao Claude Code para
  atualizar o CLAUDE.md ANTES de gerar código.
- Para tarefas longas, peça que ele quebre em passos e registre decisões em docs/.
- Se abrir uma sessão nova, ele relê o CLAUDE.md — então o que estiver lá, ele sabe;
  o que só ficou no chat anterior, ele esquece. Documente, não confie na memória de chat.
