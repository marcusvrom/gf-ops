# ops/migrate — comando único de migração para servidor novo

Orquestra a transferência do gf-server para um **destino limpo** a partir
dos artefatos versionados (bootstrap idempotente) e de um bundle do `ops/backup`.
A VM ORIGEM continua intocada — só os DADOS viajam (pg_dump), não o disco da VM.

## Premissa

> Migração = reprovisionar do zero + restaurar dump. Nunca "copiar o .vhdx".
>
> Isto força o stack a ser de fato reproduzível e impede que estado escondido
> (pacotes manuais, configs perdidas) viaje sem auditoria.

## Comando

```bash
sudo bash ops/migrate/migrate.sh <bundle.tar.zst>
```

Onde `<bundle.tar.zst>` é o conteúdo de uma pasta gerada por
`ops/backup/backup.sh` empacotado:

```bash
# Na VM ORIGEM
sudo systemctl start gf-backup.service        # ou aguarde o timer diário
cd /var/backups/gf-server
sudo tar --use-compress-program=zstd -cf bundle-$(date +%Y%m%d).tar.zst 20*Z/
scp bundle-*.tar.zst gf-new:/tmp/             # ou rclone, ou pen drive
```

Na VM DESTINO (virgem, Ubuntu 22.04, server file em `/root/gf_server/`,
`/etc/gf-server/env` preenchido):

```bash
sudo bash ops/migrate/migrate.sh /tmp/bundle-20260524.tar.zst
```

## Etapas (cada uma idempotente, cada uma com confirmação)

| # | Etapa | Faz | Pula com | Rollback |
|---|---|---|---|---|
| 1 | **preflight** | env, server file, bundle SHA256, gf.target inativo, espaço, IP válido | (não pula) | — |
| 2 | **bootstrap** | `ops/bootstrap/bootstrap.sh` (SO + PG + roles + painel + units) | `--skip-bootstrap` | snapshot zero |
| 3 | **restore** | `ops/backup/restore.sh --yes-i-really-mean-it` (DROP+CREATE+pg_restore + setval na sequence) | `--from 4` | restore do bundle ANTERIOR |
| 4 | **ip-patch** | `ops/install/04-ip-patch.sh` (dd nos binários offsets 0x3EA7A7/0x822D47 + UPDATE bancos) | `--from 5` | restaurar `.bak` dos binários |
| 4.5 | **ressync grants** | re-roda `02-grants-*.sql` (cobre objetos novos do schema) | `--skip-hardening` | — (idempotente) |
| 5 | **start** | `systemctl start gf.target` | `--from 6` | `systemctl stop` |
| 6 | **post-validate** | portas TCP + contagens vs manifest + invariante id==idnum + IP nos bancos | (não pula) | — |

`--yes` aceita todas as confirmações (CI/automação). Em uso interativo,
**não use** — cada confirmação é uma oportunidade de revisar.

## Lembrete crítico do patch de IP

O IP do servidor está **gravado dentro dos binários** WorldServer e ZoneServer
(offsets `0x3EA7A7` e `0x822D47` — ver `docs/server-files-notes.md`). Mudar de
máquina muda o IP, e o IP novo precisa ser escrito por `dd ... conv=notrunc` —
**editar `setup.ini` ou `worlds.ip` não basta**. O `04-ip-patch.sh` faz as 3
coisas (binários + worlds.ip + serverstatus.ext_address) e mantém `.bak`.

O env `GF_SERVER_HOST_IP` é o IP DO DESTINO; coloca em `/etc/gf-server/env`
antes de rodar migrate.

## Validação em VM descartável (ensaio da migração real)

Roteiro completo, testável:

1. **Preparar destino**:
   - VM Ubuntu Server 22.04 zerada (snapshot zero).
   - Copiar repo `gf-ops` para `/root/gf-ops/`.
   - Copiar server file para `/root/gf_server/` (binários do GameServer).
   - Criar `/etc/gf-server/env` (ver `ops/bootstrap/README.md` §Pré-requisitos).
2. **Preparar bundle de teste**: na VM atual com dados reais (ou em qualquer
   outra com dados de smoke), gerar o bundle e levar para o destino.
3. **Migrar**:
   ```bash
   cd /root/gf-ops
   sudo bash ops/migrate/migrate.sh /tmp/bundle.tar.zst
   ```
4. **Validar manualmente** (além do post-validate):
   - `systemctl status gf.target` → todas as units `active (running)`.
   - `journalctl -u 'gf-*.service' --since "5 min ago"` sem `error|abort`.
   - `curl -s http://<ip>/status.php` mostra "Online" nos 3 processos.
   - Cliente `GF_ES_006.058.64.64` em outra máquina logando, criando
     personagem, andando, fazendo logout e relogando — dados persistem.
5. **Rollback do ensaio**: restaurar snapshot zero. Repetir a partir de 1
   para provar que **não é a primeira execução que dá certo** — qualquer
   execução dá.

Esse ciclo (snapshot → migrate → validar → snapshot) é o ensaio que dá
confiança para a migração real.

## Pegadinhas conhecidas (e como o migrate cobre)

- **Senha SCRAM vs MD5**: roles criadas com `password_encryption=md5` (ver
  `ops/hardening/01-roles.sql`). Sem isso, libpq legado do jogo recusa auth.
- **Conexões ativas no DROP DATABASE**: `restore.sh` termina-as via
  `pg_terminate_backend` antes do DROP. preflight ainda recusa migrar com
  `gf.target` ativo, prevenindo o caso comum.
- **Sequence `account_id_seq_mvp`**: `restore.sh` faz `setval(max(id)+1)` ao
  final — impede emissão de id que já existe e quebra a invariante #1.
- **Permissões do `setup.ini`**: `05-server-config.sh` (chamado via
  bootstrap) deixa 0600 root:root; o `hardening --apply-config` mantém.
- **php-mbstring**: stage 20 do bootstrap garante. Sem ele o registro pelo
  painel falha com função indefinida em runtime.

## Não está aqui (deliberado)

- **Migração ao vivo / zero-downtime**: não. O modelo do gf-server (estado
  in-memory das zonas, sessões TCP do client) torna failover transparente
  caro. Para o MVP, parada planejada é honestamente mais barata.
- **Replicação streaming**: idem. Pode entrar no Backlog quando passar de 1
  shard.
- **Upgrade de versão do server file**: este migrate assume **mesma versão**
  do GameServer em origem e destino. Upgrade é outra coisa.
