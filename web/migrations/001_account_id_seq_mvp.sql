-- Sequence dedicada para emissão atômica de ids de conta (resolve race do MAX(id)+1).
-- A mesma sequence é usada por scripts/setup/create_account.sh e pelo painel reescrito.
-- Roda em gf_ls.
\connect gf_ls
DO $$
DECLARE maxid bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relkind='S' AND relname='account_id_seq_mvp') THEN
    SELECT COALESCE(MAX(id),0) INTO maxid FROM accounts;
    EXECUTE format('CREATE SEQUENCE account_id_seq_mvp START WITH %s', maxid + 1);
  END IF;
END $$;
