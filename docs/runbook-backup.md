# Runbook — Backup / Restore MSSQL (MVP)

> No MVP é para não perder o ambiente de teste. Em produção vira a estratégia da Seção 6 do plano.

## Backup full (manual)
```sql
BACKUP DATABASE [GrandFantasia]
TO DISK = 'C:\gf-backups\gf_full.bak'
WITH FORMAT, INIT, NAME = 'GF full', COMPRESSION;
```

## Restore
```sql
RESTORE DATABASE [GrandFantasia]
FROM DISK = 'C:\gf-backups\gf_full.bak'
WITH REPLACE;
```

## TODO (Claude Code pode automatizar)
- [ ] Script Go/PowerShell de backup agendado.
- [ ] Cópia off-site (mesmo no MVP, para outra pasta/disco).
- [ ] Teste de restore documentado.
