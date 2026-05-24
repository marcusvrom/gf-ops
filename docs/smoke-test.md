# Smoke Test — Loop Jogável do MVP

Objetivo: validar a cadeia inteira numa máquina. Cada passo exercita um componente
diferente. Se algum falha, pare e resolva antes de seguir — falhas se acumulam e
viram impossíveis de debugar juntas.

## Pré-condições

- [ ] MSSQL up e respondendo (`telnet 127.0.0.1 1433` ou equivalente).
- [ ] Schema + data restaurados sem erro.
- [ ] IP aplicado nos binários via `./install full` ou `./install ip` (patch hex nos offsets).
- [ ] AccountServer e ZoneServer iniciados sem erro de conexão ao DB nos logs.
- [ ] Patch server HTTP servindo o cliente (se aplicável).
- [ ] Cliente patchado para `127.0.0.1`.

## Loop principal (a métrica de pronto)

| # | Ação | Componente exercitado | Falha comum |
|---|------|----------------------|-------------|
| 1 | Registrar conta | AccountServer + DB (write) | Conta não persiste → checar conexão DB / permissão de escrita |
| 2 | Logar | AccountServer (auth) | Senha/hash divergente → checar formato de hash esperado |
| 3 | Ver lista de personagens | Account + DB (read) | Lista vazia/erro → checar tabela de personagens |
| 4 | Criar personagem | DB (write) | Falha de FK → ordem/integridade do schema |
| 5 | **Entrar no mundo** | Handoff Login → World → Zone | **Trava no loading → IP errado no patch binário; rodar `./install ip`** |
| 6 | Andar | ZoneServer (movimento) | Player não move → pacote de movimento / colisão de mapa |
| 7 | Matar um mob | ZoneServer (combate + spawn) | Sem mobs → data de spawn não carregada |
| 8 | Upar (ganhar XP) | ZoneServer + DB (rates) | XP não sobe → config de [Rates] |
| 9 | **Trocar de mapa** | Transição entre zonas | Trava → mapeamento mapa→zona no .ini |
| 10 | Deslogar e relogar | Persistência completa | Progresso perdido → save não escreveu no DB |

## Validação GM (após o loop fechar)

- [ ] Criar conta com flag GM (documentar como em `server-files-notes.md`).
- [ ] Comando de spawn de item funciona.
- [ ] Comando de teleport funciona.
- [ ] Ação de GM aparece nos logs (base para auditoria futura).

## Critério de aceitação do MVP

✅ Passos 1–10 completados em sequência, com o progresso do passo 8 persistindo
após o relogin do passo 10.

## Se travar no passo 5 (o mais comum)

1. Login funciona mas mundo não = o IP gravado nos binários WorldServer/ZoneServer está errado.
2. O IP é PATCH BINÁRIO (offsets 0x3EA7A7 / 0x822D47), não config — re-rodar `./install ip`.
3. Conferir também `worlds.ip` (gf_ls) e `serverstatus.ext_address` (gf_gs) no PostgreSQL.
4. Reiniciar os processos após o re-patch.
5. Em LAN/VM, usar o IP real da interface (o script ignora 127.0.0.1).
