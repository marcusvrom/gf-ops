# GF-MVP — Grand Fantasia Private Server (MVP)

MVP local de um servidor privado de Grand Fantasia. Objetivo: fechar o loop jogável
numa única máquina antes de pensar em escala.

> **Critério de pronto do MVP:** registrar conta → logar → entrar no mundo → andar →
> matar mob → upar → trocar de mapa, com dados persistindo no MSSQL local.

## Pré-requisitos

- Windows (os binários do servidor exigem) — pode ser uma VM.
- Microsoft SQL Server Express.
- Server files de GF + cliente da **mesma versão** (alvo: client 109).
- .NET SDK (painel/bot) e Rust toolchain (tooling de ops/load-test) — conforme o componente.
- Claude Code (plano Pro/Max/Team/Console) para acelerar o tooling.

## Como usar este repo

1. Leia `CLAUDE.md` — é o mapa do projeto e o contexto do Claude Code.
2. Siga o checklist em `docs/smoke-test.md`.
3. Atualize a tabela de estado na Seção 5 do `CLAUDE.md` a cada avanço.

## Camadas do projeto

- **Binários do servidor** (AccountServer/ZoneServer): fechados, Windows. Configuramos, não desenvolvemos.
- **Tooling ao redor**: código nosso, **poliglota por componente** (sem Go). É aqui que o Claude Code trabalha:
  - `web/` e `bot/` → C#/.NET (conversa com MSSQL e usuários).
  - `tools-rs/` → Rust (binários para a VM: confcheck, healthcheck, load test).
  - `ops/` → PowerShell (orquestração MSSQL no Windows).

## Aviso

Projeto de preservação/comunidade, sem fins lucrativos. Veja restrições no `CLAUDE.md` §7.
