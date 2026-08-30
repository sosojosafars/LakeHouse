-- Silver: pedidos tipados, com valor líquido zerado para cancelados.
-- valor_liquido pode ser negativo em pedidos não cancelados: item devolvido
-- é negócio legítimo (ver silver.itens_pedido), não sujeira.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pedidos AS
WITH base AS (
  SELECT *, COUNT(*) OVER () AS _linhas_origem
  FROM lakehouse_rotaperfume.bronze.pedidos
),
tipado AS (
  SELECT
    pedido_id,
    cliente_id,
    vendedor_id,
    coalesce(try_to_date(data_pedido), try_to_date(data_pedido, 'dd/MM/yyyy')) AS data_pedido,
    canal,
    status,
    status = 'Cancelado' AS cancelado,
    TRY_CAST(valor_total AS DECIMAL(18,2)) AS valor_total,
    _linhas_origem
  FROM base
)
SELECT
  pedido_id,
  cliente_id,
  vendedor_id,
  data_pedido,
  canal,
  status,
  cancelado,
  valor_total,
  CASE WHEN cancelado THEN CAST(0 AS DECIMAL(18,2)) ELSE valor_total END AS valor_liquido,
  year(data_pedido) AS ano,
  month(data_pedido) AS mes,
  current_timestamp() AS _processado_em,
  _linhas_origem
FROM tipado;

ALTER TABLE lakehouse_rotaperfume.silver.pedidos ADD CONSTRAINT data_pedido_nao_nula CHECK (data_pedido IS NOT NULL);
ALTER TABLE lakehouse_rotaperfume.silver.pedidos ADD CONSTRAINT pedido_cancelado_zerado CHECK (NOT cancelado OR valor_liquido = 0);

COMMENT ON TABLE lakehouse_rotaperfume.silver.pedidos IS
  'Pedidos tipados. valor_liquido é zero para pedidos cancelados, valor_total caso contrário.';

ALTER TABLE lakehouse_rotaperfume.silver.pedidos ALTER COLUMN data_pedido COMMENT
  'Convertida com try_to_date cobrindo ISO e dd/MM/yyyy — to_date abortaria em ANSI mode com data malformada.';
ALTER TABLE lakehouse_rotaperfume.silver.pedidos ALTER COLUMN cancelado COMMENT
  'Deriva de status = Cancelado: a origem zera valor_total sem nenhuma flag explícita própria.';
ALTER TABLE lakehouse_rotaperfume.silver.pedidos ALTER COLUMN valor_liquido COMMENT
  'Zero quando cancelado, valor_total caso contrário. Pode ser negativo em pedidos não cancelados com item devolvido — não é sujeira, é a constraint proposital (ver pedido_cancelado_zerado, não valor_liquido >= 0).';
