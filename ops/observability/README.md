# ops/observability — métricas para o gf-server

**Tudo aqui é opcional.** O `gf.target` roda sem nada disso. Estes componentes
apenas **expõem** métricas; agregação (Prometheus) e visualização (Grafana)
ficam num host separado, fora do MVP.

## Princípios

1. **Sem acoplamento com `gf.target`.** Nenhuma unit aqui declara
   `Requires=gf.target`. A sonda de portas, inclusive, existe **justamente**
   para reportar quando o gf cai — então tem que estar viva enquanto ele estiver morto.
2. **Sem Prometheus/Grafana na VM.** Roda em qualquer outro lugar (sua máquina,
   um VPS de monitoração, Grafana Cloud free tier). Este repo só fornece:
   - `prometheus.example.yml` — colar no Prometheus externo.
   - `grafana-dashboard.example.json` — importar no Grafana externo.
3. **Tudo idempotente, tudo binário oficial ou pacote do apt.** Sem container.
4. **Privilégio mínimo.** Role `gf_exporter` com `pg_monitor` + `SELECT` (não escreve nada).

## Estrutura

```
ops/observability/
├── README.md
├── install.sh                         # orquestrador (cada etapa opcional)
├── install-node-exporter.sh           # apt: prometheus-node-exporter + textfile collector
├── install-postgres-exporter.sh       # binário oficial v0.15, role gf_exporter
├── install-probe.sh                   # sonda TCP das portas + textfile
├── postgres-exporter.service          # systemd unit
├── postgres-exporter-queries.yml      # custom queries (contas, chars, gold, AP, invariante)
├── probe/
│   ├── gf-port-probe.sh               # /dev/tcp + escrita atômica no textfile
│   ├── gf-port-probe.service
│   └── gf-port-probe.timer            # cada 30s
├── prometheus.example.yml             # scrape config PRONTO PRA COLAR
└── grafana-dashboard.example.json     # dashboard MÍNIMO pra importar
```

## O que vira métrica

### node_exporter (`:9100`)
- Todas as métricas padrão (`node_cpu_seconds_total`, `node_memory_*`, etc).
- + Textfile do probe:
  - `gf_port_up{service="login|gateway|ticket|world",port="..."}` — 0/1.
  - `gf_port_probe_timestamp_seconds` — quando rodou pela última vez.

### postgres_exporter (`:9187`)
- Stats nativos do PG (`pg_stat_database_*`, `pg_locks_count`, etc).
- + Custom queries (`postgres-exporter-queries.yml`):
  - `gf_accounts_total` — contas em `gf_ls.accounts`.
  - `gf_characters_total`, `gf_characters_max_level`, `gf_characters_avg_level`.
  - `gf_gold_gold_total`, `gf_gold_gold_max`, `gf_gold_gold_avg` — base p/ detectar inflação.
  - `gf_gold_crystal_total`.
  - `gf_premium_ap_total`, `gf_premium_ap_capped` — contas no teto de 99999 (sinal de dupe).
  - `gf_invariant_id_idnum_ls_count` + `gf_invariant_tb_user_count_ms_count` — se divergirem,
    a invariante #1 do CLAUDE.md está em risco. Alerta sugerido no `prometheus.example.yml`.

## Setup

```bash
# Tudo (com confirmação por etapa)
sudo bash ops/observability/install.sh

# Ou seletivo:
sudo bash ops/observability/install-node-exporter.sh
sudo bash ops/observability/install-postgres-exporter.sh
sudo bash ops/observability/install-probe.sh
```

Conferir local:
```bash
curl -s http://127.0.0.1:9100/metrics | grep '^gf_port_up'
curl -s http://127.0.0.1:9187/metrics | grep -E '^(pg_up|gf_)'
```

## Plugar num Prometheus externo

1. Garanta acesso de rede do Prometheus à VM nas portas `9100` e `9187`. Em LAN
   privada / Hyper-V, túnel SSH é o caminho mais barato:
   ```bash
   # do host do Prometheus, p/ a VM:
   ssh -L 9100:127.0.0.1:9100 -L 9187:127.0.0.1:9187 user@gf-vm
   ```
   E o `prometheus.example.yml` aponta para `localhost:9100` / `localhost:9187`.
2. Cole o conteúdo de `prometheus.example.yml` (ajustando o IP) no `prometheus.yml`
   do servidor externo. Recarregue.
3. No Grafana, datasource Prometheus apontando para o servidor de Prometheus.
   Importe `grafana-dashboard.example.json` (Dashboards → Import → Upload JSON).

## Notas de segurança

- `postgres_exporter` escuta em **`127.0.0.1:9187`** por padrão na unit. Não expõe
  na rede; o Prometheus externo precisa de túnel ou de uma alteração explícita em
  `--web.listen-address`. Decisão deliberada: senha do `gf_exporter` está em
  `/etc/gf-server/exporter.env` e o role tem `pg_monitor` — se a porta vazasse,
  alguém com acesso a métricas teria visão de stats internos do banco.
- `node_exporter` escuta em **`:9100`** (todas as interfaces), padrão Ubuntu. Em
  VM exposta, restrinja por firewall ou faça túnel também.

## O que NÃO está aqui

- **Alertmanager**: configuração de alertas (Discord/email) vive no host do
  Prometheus. Regras de exemplo comentadas em `prometheus.example.yml`.
- **Loki / logs**: o `journalctl -u gf-*` é suficiente no MVP. Quando precisar
  centralizar, `promtail` na VM apontando p/ Loki externo é trivial.
- **Tracing**: nada aqui é tracing. Os binários ELF são caixa-preta.
- **cAdvisor**: não há containers.
