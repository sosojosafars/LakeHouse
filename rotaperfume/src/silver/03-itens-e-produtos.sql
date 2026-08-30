-- Silver: produtos tipados e itens_pedido com devolução sinalizada (nunca
-- descartada). sku_descontinuado cruza com produtos para marcar itens de um
-- SKU que não está mais ativo hoje.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.produtos AS
WITH base AS (
  SELECT *, COUNT(*) OVER () AS _linhas_origem
  FROM lakehouse_rotaperfume.bronze.produtos
)
SELECT
  sku,
  descricao,
  categoria,
  marca,
  nota_olfativa,
  TRY_CAST(preco_tabela AS DECIMAL(18,2)) AS preco_tabela,
  TRY_CAST(custo_unitario AS DECIMAL(18,2)) AS custo_unitario,
  unidade,
  ativo = 'S' AS ativo,
  coalesce(try_to_date(data_lancamento), try_to_date(data_lancamento, 'dd/MM/yyyy')) AS data_lancamento,
  current_timestamp() AS _processado_em,
  _linhas_origem
FROM base;

COMMENT ON TABLE lakehouse_rotaperfume.silver.produtos IS
  'Catálogo de produtos tipado: preços em DECIMAL, ativo como boolean, data_lancamento convertida com try_to_date.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.itens_pedido AS
WITH base AS (
  SELECT *, COUNT(*) OVER () AS _linhas_origem
  FROM lakehouse_rotaperfume.bronze.itens_pedido
),
tipado AS (
  SELECT
    item_id,
    pedido_id,
    sku,
    TRY_CAST(quantidade AS INT) AS quantidade,
    TRY_CAST(preco_praticado AS DECIMAL(18,2)) AS preco_praticado,
    TRY_CAST(desconto_pct AS DECIMAL(9,4)) AS desconto_pct,
    TRY_CAST(valor_bruto AS DECIMAL(18,2)) AS valor_bruto,
    _linhas_origem
  FROM base
)
SELECT
  t.item_id,
  t.pedido_id,
  t.sku,
  t.quantidade < 0 AS devolucao,
  abs(t.quantidade) AS quantidade_abs,
  t.preco_praticado,
  t.desconto_pct,
  t.valor_bruto,
  NOT coalesce(p.ativo, true) AS sku_descontinuado,
  current_timestamp() AS _processado_em,
  t._linhas_origem
FROM tipado t
LEFT JOIN lakehouse_rotaperfume.silver.produtos p ON t.sku = p.sku;

ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido ADD CONSTRAINT quantidade_abs_positiva CHECK (quantidade_abs > 0);

COMMENT ON TABLE lakehouse_rotaperfume.silver.itens_pedido IS
  'Itens de pedido tipados. Quantidade negativa na origem é devolução, sinalizada em devolucao — a linha é sempre preservada.';

ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido ALTER COLUMN devolucao COMMENT
  'quantidade < 0 na origem é devolução, não erro — a linha é preservada, nunca descartada.';
ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido ALTER COLUMN quantidade_abs COMMENT
  'Valor absoluto de quantidade, sempre positivo (ver constraint quantidade_abs_positiva). Use devolucao para saber o sinal original.';
ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido ALTER COLUMN sku_descontinuado COMMENT
  'true quando o produto referenciado não está mais ativo em silver.produtos no momento do processamento.';
