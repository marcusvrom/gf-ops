# ops/backup — backup off-site dos 3 bancos

Substitui o `./server backup` original (`docs/server-script-reference.txt`),
mantendo a parte boa (pg_dump dos 3 bancos) e corrigindo o resto:

| `./server backup` original | Aqui |
|---|---|
| `pg_dump -Fp` (plain SQL, gigante, restore só serial) | `pg_dump -Fc` (custom, comprimido, `pg_restore -j` paralelo) |
| `chmod -R 777 /root` ao final | **Removido**. Diretório `0750 root:root`. |
| Senha lida via `read` interativo | Lida de `/etc/gf-server/env`; pode rodar via timer sem prompt. |
| Sem off-site, sem retenção, sem checksum | Off-site via SSH **ou** rclone; retenção configurável; `SHA256SUMS` + `manifest.json` por backup. |
| Restore via `./server restore` faz `chmod 777` de novo | `restore.sh` exige `--yes-i-really-mean-it` + servidor parado. |
| Sem teste de restore | `verify-restore.sh` restaura em bancos temporários e valida invariante id==idnum. |

## Estrutura

```
ops/backup/
├── README.md
├── env.example           # adicionar a /etc/gf-server/env
├── backup.sh             # dump + checksum + manifest + off-site + retenção
├── restore.sh            # DESTRUTIVO: --yes-i-really-mean-it
├── verify-restore.sh     # smoke test do backup em DBs temporários
├── install.sh            # copia scripts + ativa timer
├── gf-backup.service     # oneshot
└── gf-backup.timer       # diário 03:17 UTC + Persistent=true
```

## Modos off-site

Configurados no `/etc/gf-server/env`:

- `GF_BACKUP_SSH='user@host:/srv/backups/gf-server/'` → `rsync` por SSH. Pré-req: chave do root local autorizada no destino.
- `GF_BACKUP_RCLONE='b2:bucket/gf/'` → `rclone copy`. Pré-req: `~/.config/rclone/rclone.conf` do root.

Os dois podem coexistir (envia para ambos). Se nenhum estiver setado, só fica local.

## Layout de um backup

```
/var/backups/gf-server/20260524T031700Z/
├── gf_gs.dump          # pg_dump -Fc
├── gf_ls.dump
├── gf_ms.dump
├── SHA256SUMS          # checksums dos 3 dumps
└── manifest.json       # timestamp, host, PG version, contagens-chave
```

Publicação **atômica**: o backup só ganha o nome final (sem `.tmp`) depois que tudo
foi escrito. Se a VM cair no meio, o `.tmp` fica para inspeção, mas a retenção
não o trata como backup válido.

## Operação

```bash
# Instalação inicial (uma vez)
sudo bash ops/backup/install.sh

# Rodar AGORA (sob demanda)
sudo systemctl start gf-backup.service
journalctl -u gf-backup -f

# Validar o backup mais recente (não-destrutivo, usa DBs temporários)
sudo bash ops/backup/verify-restore.sh

# Validar um específico
sudo bash ops/backup/verify-restore.sh /var/backups/gf-server/20260524T031700Z

# Restaurar produção a partir de um backup (destrutivo)
sudo systemctl stop gf.target
sudo bash ops/backup/restore.sh /var/backups/gf-server/20260524T031700Z --yes-i-really-mean-it
sudo systemctl start gf.target
```

## Decisões e trade-offs

### `pg_dump -Fc` (custom) em vez de `-Fp` (plain SQL)
- ~10× menor (compressão interna nível 9).
- Permite `pg_restore -j N` paralelo. Em bancos com 113 tabelas no `gf_gs`,
  importa de verdade.
- Permite restaurar **parcialmente** (`pg_restore -t auction`).
- Custo: não dá pra `psql -f gf_gs.dump`. Precisa de `pg_restore`.
  Aceitável — o restore.sh já usa.

### `--no-owner --no-privileges` no dump e restore
- O dump não carrega o `OWNER postgres` (legado do install original).
- No restore, recriamos o banco com `OWNER gf_app` (matches do install hardened)
  e fazemos `REASSIGN OWNED`. Sem isso, restaurar num cluster hardened deixaria
  tabelas com owner postgres (vaza superuser de novo).

### Manifest com contagens
São snapshots de **3 tabelas-chave**:
- `gf_ls.accounts` — total de contas.
- `gf_ms.tb_user` — invariante #1 do CLAUDE.md (deve ter mesma contagem que `accounts`).
- `gf_gs.player_characters` — atividade dos jogadores.

`verify-restore.sh` re-conta no restore e compara com o manifest. Se diferir,
o backup está corrompido (ou o pg_restore falhou silenciosamente).

### Verificação da invariante crítica
`verify-restore.sh` faz mais que conferir contagem: vai conta a conta validando
que `gf_ls.accounts.id == gf_ms.tb_user.idnum` (CLAUDE.md §6 #1). Se algum par
não bater no backup, o restore corromperia o login — e queremos saber **antes**
de mexer em produção.

### Timer 03:17 UTC com jitter
Hora "morta" pra um MMORPG (qualquer fuso), `RandomizedDelaySec=5min` distribui
se houver vários servidores, `Persistent=true` recupera se a VM estava desligada
na hora marcada.

### O que NÃO está aqui
- **Criptografia at rest** (`age`/`gpg`): O destino off-site é o lugar certo pra
  isso (cliente do bucket cifra antes de subir, ou bucket tem encryption-at-rest).
  Dá pra adicionar `age --recipients-file ...` num pipe no `backup.sh` quando
  decidir a UX — fica fora do MVP.
- **PITR / WAL archiving** (`archive_mode=on` + base backup): infra real de
  banco. Para um MVP em 1 VM, dump diário é suficiente. Quando passar de 1
  shard ou de SLA de minutos, migrar para `pgbackrest` ou `barman`.
- **Notificação em falha**: hoje só vai pro journal. Quando tiver Discord bot
  (backlog), `OnFailure=` aponta para um service que faz POST no webhook.
