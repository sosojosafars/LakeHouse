-- Três views comerciais, para a pergunta que escapa da fila_semanal: a fila
-- só tem os 200 escolhidos desta semana; estas views cobrem os outros 2.616
-- clientes e as duas perguntas que a direção sempre faz depois — "quais
-- marcas seguram a receita" e "a receita está subindo ou caindo". São VIEW,
-- não TABLE: barato de recalcular a cada run, e nenhuma delas precisa de
-- histórico próprio — sempre refletem o fato_vendas/features_cliente atuais.

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.clientes_em_risco AS
SELECT
  f.cliente_id,
  c.razao_social,
  c.segmento,
  c.cidade,
  c.uf,
  f.recencia_dias,
  f.intervalo_medio_dias,
  ROUND(f.atraso_relativo, 2) AS atraso_relativo,
  f.valor_total,
  f.ticket_medio,
  f._referencia
FROM lakehouse_rotaperfume.gold.features_cliente f
JOIN lakehouse_rotaperfume.gold.dim_cliente c ON c.cliente_id = f.cliente_id
WHERE f.atraso_relativo > 1;

COMMENT ON TABLE lakehouse_rotaperfume.gold.clientes_em_risco IS
  'Clientes fora da fila_semanal mas em risco: já passaram do próprio ciclo de recompra (atraso_relativo > 1). Grão: cliente. Fonte: gold.features_cliente + gold.dim_cliente, corte em features_cliente._referencia.';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.clientes_em_risco.atraso_relativo IS
  'recencia_dias / intervalo_medio_dias do cliente: > 1 significa que ele já está mais tempo sem comprar do que o próprio ritmo histórico prevê. Mesma métrica que ordena fila_semanal.';

-- ranking de marcas ------------------------------------------------------------

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.ranking_marcas AS
WITH agregado AS (
  SELECT
    marca,
    SUM(receita) AS receita,
    SUM(margem) AS margem,
    SUM(quantidade) AS quantidade,
    COUNT(DISTINCT cliente_id) AS clientes_distintos
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY marca
)
SELECT
  marca,
  receita,
  margem,
  ROUND(100 * margem / NULLIF(receita, 0), 2) AS margem_pct,
  quantidade,
  clientes_distintos,
  ROUND(100 * receita / SUM(receita) OVER (), 2) AS participacao_pct,
  RANK() OVER (ORDER BY receita DESC) AS posicao
FROM agregado;

COMMENT ON TABLE lakehouse_rotaperfume.gold.ranking_marcas IS
  'Todas as marcas ordenadas por receita, com margem e participação no total. Grão: marca. Conforma com fato_vendas (mesma receita agregada — teste 11).';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.ranking_marcas.participacao_pct IS
  'Percentual da receita total da empresa que esta marca representa (SUM(receita) desta marca / SUM(receita) de todas).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.ranking_marcas.posicao IS
  'Posição da marca no ranking por receita, 1 = maior receita. Empates recebem o mesmo posicao (RANK, não ROW_NUMBER).';

-- receita mensal ------------------------------------------------------------

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.receita_mensal AS
SELECT
  ano,
  mes,
  SUM(receita) AS receita,
  SUM(margem) AS margem,
  ROUND(100 * SUM(margem) / NULLIF(SUM(receita), 0), 2) AS margem_pct,
  COUNT(DISTINCT pedido_id) AS pedidos_distintos,
  COUNT(DISTINCT cliente_id) AS clientes_distintos
FROM lakehouse_rotaperfume.gold.fato_vendas
GROUP BY ano, mes;

COMMENT ON TABLE lakehouse_rotaperfume.gold.receita_mensal IS
  'Receita e margem por ano/mês do pedido. Grão: ano x mês. Conforma com fato_vendas (mesma receita agregada — teste 12).';

COMMENT ON COLUMN lakehouse_rotaperfume.gold.receita_mensal.margem_pct IS
  'Margem do mês dividida pela receita do mês, em percentual.';
