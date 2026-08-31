-- gold.retorno_ligacao — o caminho de volta. Três noites construíram o
-- caminho de ida (a quem ligar); esta tabela é onde o time registra o que
-- aconteceu depois da ligação.
--
-- É a ÚNICA tabela do projeto cujo dado não vem do pipeline — vem do time,
-- pelo Genie ou por um formulário. Por isso CREATE TABLE IF NOT EXISTS, e
-- NUNCA CREATE OR REPLACE: um redeploy não pode apagar o que o vendedor já
-- respondeu. Nasce vazia; resposta vazia (zero linhas) é o estado correto no
-- início — o Genie de direção é instruído a dizer isso, nunca inventar.
--
-- COMMENT em toda coluna, sem exceção: a auditoria de metadado (teste 10 em
-- 08-testes.sql) quebra o job se faltar uma.
CREATE TABLE IF NOT EXISTS lakehouse_rotaperfume.gold.retorno_ligacao (
  cliente_id      INT       NOT NULL,
  vendedor        STRING    NOT NULL,
  status          STRING    NOT NULL,
  comentario      STRING,
  registrado_em   TIMESTAMP NOT NULL,
  registrado_por  STRING    NOT NULL,
  _referencia     DATE      NOT NULL
);

COMMENT ON TABLE lakehouse_rotaperfume.gold.retorno_ligacao IS
  'O que aconteceu depois de cada ligação da fila_semanal, registrado pelo time — não pelo pipeline. Nasce vazia (0 linhas) e cresce só com o que o vendedor confirma. Um cliente pode ter mais de um registro ao longo do tempo (reincidência na fila); para o estado atual de um cliente, use o mais recente por registrado_em.';

ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN cliente_id COMMENT
  'Cliente que recebeu a ligação. Corresponde a gold.fila_semanal.cliente_id / gold.score_propensao.cliente_id (ambos INT).';
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN vendedor COMMENT
  'Nome do vendedor que fez a ligação — mesmo texto de gold.fila_semanal.vendedor (gold.dim_vendedor.nome).';
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN status COMMENT
  'Resultado da ligação. Único vocabulário válido: vendeu | vai_pensar | sem_interesse | nao_atendeu.';
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN comentario COMMENT
  'Texto livre do vendedor sobre a ligação. Pode ser NULL — nem toda ligação gera comentário.';
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN registrado_em COMMENT
  'Timestamp de quando o retorno foi registrado — não o timestamp da ligação em si, que este projeto não captura.';
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN registrado_por COMMENT
  'E-mail de quem estava logado ao registrar o retorno — auditoria de quem lançou o dado, não necessariamente quem ligou.';
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao ALTER COLUMN _referencia COMMENT
  'Semana da fila (gold.fila_semanal) a que esta ligação se refere — permite juntar o retorno à fila que o originou mesmo depois que fila_semanal for recalculada para a semana seguinte.';
