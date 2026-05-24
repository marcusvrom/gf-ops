# scripts/sql/audit — auditoria de economia e integridade

Queries `psql -f` que **não escrevem nada** nos bancos. São lentas em proporção
ao tamanho dos dados, mas o pior caso continua sendo segundos (não minutos) num
servidor de até alguns milhares de contas.

## Catálogo

| Arquivo | Banco | O que detecta |
|---|---|---|
| `01-gold-flux.sql` | gf_gs | fluxo diário `increase`/`decrease`/net; alerta de **inflação 7d/21d ≥ 2x** |
| `02-gold-distribution.sql` | gf_gs | distribuição em `range1..range10`; evolução do topo (top 2 faixas) |
| `03-gold-outliers.sql` | gf_gs | top 20 por gold/crystal; **gold ≥ 50× a mediana** (level ≥ 10) |
| `04-ap-cap.sql` | gf_ms | contas em `pvalues=99999`; contas **acima** do teto (bug/injeção) |
| `05-auction-extremes.sql` | gf_gs | lances **≥ 100× a mediana** do mesmo item (vetor clássico de dupe) |
| `06-gm-privilege.sql` | (3) | inventário cross-tabela de GMs nos 3 lugares; sinal do bug `gm_tool_account` singular |
| `07-invariant-id-idnum.sql` | gf_ls | invariante #1 do CLAUDE.md via `dblink` |
| `run-audit.sh` | wrapper | roda tudo, arquiva relatório, faz a invariante #1 **sem dblink** |

## Uso

```bash
# Rodar tudo + arquivar em /var/log/gf-audit/
sudo bash scripts/sql/audit/run-audit.sh

# Rápido (pula auction-extremes)
sudo bash scripts/sql/audit/run-audit.sh --quick

# Só stdout, sem arquivar
sudo bash scripts/sql/audit/run-audit.sh --no-archive

# Query individual
sudo -u postgres psql -d gf_gs -f scripts/sql/audit/01-gold-flux.sql
```

O wrapper roda como `postgres` (peer) — não precisa de senha. Para rodar como
`gf_app`, exporte `PGPASSWORD` e ajuste as 3 linhas `$PSQL=` no script.

## Heurísticas — o que esperar e quando preocupar

Nenhuma delas é prova; são gatilhos pra investigar. Calibre os thresholds
conforme seu servidor cresce — ficaram conservadores pro MVP.

- **Inflação 7d/21d ≥ 2x** (`01`): o avg(increase) dobrou. Pode ser evento sazonal
  legítimo. Cruze com `02-gold-distribution.sql`: se o topo cresceu, é dupe;
  se distribuiu, é injeção saudável (evento, drop rate).
- **Gold ≥ 50× mediana** (`03`): muito raro num servidor MVP saudável. Em
  servidor estabelecido com economia ativa, considere subir pra 200×.
- **Auction ≥ 100× mediana** (`05`): venda inflada entre contas conluiadas
  (P&D — laundering). Filtre por `seller_id` recorrente nas reclamações.
- **AP acima de 99999** (`04`): só acontece se alguém escreveu **fora do painel**.
  O painel reescrito (`web/admin/gold.php`) re-checa o teto server-side.
- **GMs descasados** (`06`): GM em `player_characters` sem entrada em
  `gm_tool_accounts`, ou vice-versa, é resíduo do bug do painel antigo. O
  painel reescrito já grava nos 3 lugares; ainda assim, audite após restaurar
  backups antigos.
- **`run-audit.sh` parte 7** (`id != idnum`): **inegociável**. Qualquer divergência
  é login quebrado. Causa típica: alguém criou conta direto no SQL, fora do
  `create_account.sh` / do painel.

## Integração com a observabilidade

As métricas custom de `ops/observability/postgres-exporter-queries.yml` já
publicam vários destes valores como gauges (`gf_gold_gold_total`,
`gf_premium_ap_capped`, `gf_invariant_*`). O dashboard de exemplo
(`grafana-dashboard.example.json`) mostra `deriv(gf_gold_gold_total[10m])`
como sinal contínuo de inflação. Estas queries SQL são o **drill-down**
quando o gauge alerta: o exporter avisa "tem algo errado", os SQLs respondem
"foi este personagem / leilão / dia".

## Limitações conhecidas

- `auction` em estado avançado costuma ter muitos `item_id` distintos.
  `05` filtra por `>= 5` leilões — itens raros (que são justamente os
  duplicados!) ficam de fora. Para itens raros, faça lookup direto por
  `item_id` específico depois que alguém reclamar.
- Não há `gold_log` por personagem; o agregador é global (gold do servidor
  inteiro por dia). Para rastrear o autor de um pico, é preciso instrumentar
  na fonte — coisa da Camada A, fora do escopo.
- Heurística de outlier (gold ≥ 50× mediana) é estatisticamente fraca quando
  N de chars é pequeno (< 100). Em MVP em VM isolada, espere falsos
  positivos; em servidor com base ativa, espere fechar.
