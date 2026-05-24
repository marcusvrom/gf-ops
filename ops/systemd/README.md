# systemd units — Grand Fantasia Private Server

Substitui o `~/gf_server/server start|stop` por gerenciamento via systemd: ordem causal
de boot garantida por `Requires=`/`After=`, restart automático em falha, log por processo
no `journald` (resolve o `&>/dev/null` do script original).

## Conteúdo

| Arquivo | Papel |
|---|---|
| `gf-ticket.service`  | TicketServer (`-p 7777`) — primeiro a subir |
| `gf-gateway.service` | GatewayServer — depende de `gf-ticket` |
| `gf-login.service`   | LoginServer — depende de `gf-gateway` |
| `gf-mission.service` | MissionServer — depende de `gf-login` |
| `gf-world.service`   | WorldServer — depende de `gf-mission` |
| `gf-zone.service`    | ZoneServer — depende de `gf-world` |
| `gf.target`          | Orquestrador (puxa os 6 services) |
| `install.sh`         | Copia units, `daemon-reload`, `enable` |
| `uninstall.sh`       | Para e remove tudo |

A cadeia `Requires=`/`After=` substitui o `sleep 2` do `server` original e impõe a ordem
**causal** descrita no `CLAUDE.md` §6: TicketServer ANTES do LoginServer, senão ECONNREFUSED
no `127.0.0.1:7777`.

## Pré-requisitos (invariantes do CLAUDE.md §6)

As 3 invariantes de SO são **obrigatórias** — sem elas os binários 32-bit nem sobem:

```bash
# locale C
sudo update-locale LANG=C LC_ALL=C   # também aplicado por Environment= em cada unit

# libs i386
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install -y libc6:i386 libstdc++6:i386 libgcc-s1:i386 zlib1g:i386

# nscd (resolve SIGSEGV em getaddrinfo via /var/run/nscd/socket)
sudo apt install -y nscd
sudo systemctl enable --now nscd
grep -q '^hosts:.*files' /etc/nsswitch.conf  # esperar: 'hosts: files dns'

# PostgreSQL 13 já rodando, com os bancos gf_gs/gf_ls/gf_ms criados
sudo systemctl status postgresql
```

Os binários do servidor devem estar em `/root/gf_server/{TicketServer,GatewayServer,
LoginServer,MissionServer,WorldServer,ZoneServer}/` (padrão do server file). Se o seu
deploy usa outro caminho, ajuste com:

```bash
sudo sed -i 's|/root/gf_server|/seu/caminho|g' /etc/systemd/system/gf-*.service
sudo systemctl daemon-reload
```

## Instalação

```bash
cd ops/systemd
sudo ./install.sh
sudo systemctl start gf.target
```

## Operação

```bash
# subir / descer tudo
sudo systemctl start gf.target
sudo systemctl stop  gf.target          # para na ordem inversa por causa do Requires=

# status global
systemctl status gf.target
systemctl list-dependencies gf.target

# log de um processo específico (em tempo real)
journalctl -u gf-login -f
journalctl -u gf-world --since "10 min ago"

# log de TODOS os serviços do gf, intercalado
journalctl -u 'gf-*.service' -f

# reiniciar apenas um (cuidado: zone/world têm dependentes implícitos no client)
sudo systemctl restart gf-zone
```

## Decisões e TODOs explícitos

- **Roda como root.** Os binários assumem `/root/gf_server` e `chmod 777 *` no script original.
  Mover para usuário dedicado faz parte do hardening (backlog §8 item 3), não deste item.
- **`Restart=on-failure`, não `always`.** Se um processo abortar repetidamente
  (ex.: faltou `nscd`), queremos que o systemd marque `failed` em vez de loop infinito.
- **Sem `ExecStop=` custom.** O default (SIGTERM → SIGKILL após `TimeoutStopSec`) é melhor
  que o `killall -9` do `server` original — dá chance de flush.
- **Sem `User=`/`Group=` por enquanto.** Idem hardening.
- **`SyslogIdentifier=gf-<nome>`** permite filtrar via `journalctl -t gf-login` além de `-u`.

## Verificação rápida pós-boot

```bash
# Todas as portas esperadas escutando (CLAUDE.md §6 / runtime)
ss -ltn | grep -E ':(7777|5560|6543|5567)\b'

# Cada processo vivo
pgrep -a TicketServer GatewayServer LoginServer MissionServer WorldServer ZoneServer
```

Se uma unit ficar em `activating` por muito tempo, capturar o syscall trace:

```bash
sudo strace -f -e trace=network,signal -p "$(pgrep LoginServer)"
journalctl -u gf-login -n 200
```
