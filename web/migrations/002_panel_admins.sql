-- Auth do painel (independente do login do jogo).
-- Senha em bcrypt via password_hash(). NÃO afeta o LoginServer, que continua MD5.
\connect gf_ls
CREATE TABLE IF NOT EXISTS panel_admins (
  id            serial PRIMARY KEY,
  username      varchar(40) UNIQUE NOT NULL,
  password_hash text NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_login_at timestamptz
);
