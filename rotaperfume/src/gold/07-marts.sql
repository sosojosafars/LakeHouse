-- Três data marts, um por diretoria, todos sobre o MESMO fato_vendas.
-- O que separa um mart do outro é a dimensão dominante e as métricas —
-- nunca uma tabela base diferente. Todos têm que conformar (somar igual).

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor AS
WITH agregado AS (
  SELECT
    vendedor_id,
    ano,
    mes,
    SUM(receita) AS receita,
    SUM(margem) AS margem,
    COUNT(DISTINCT cliente_id) AS clientes_atendidos,
    COUNT(DISTINCT pedido_id) AS pedidos_distintos
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY vendedor_id, ano, mes
)
SELECT
  a.vendedor_id,
  v.nome,
  a.ano,
  a.mes,
  a.receita,
  a.margem,
  v.meta_mensal AS meta,
  a.receita / NULLIF(v.meta_mensal, 0) AS atingimento,
  a.clientes_atendidos,
  a.receita / NULLIF(a.pedidos_distintos, 0) AS ticket_medio,
  current_timestamp() AS _processado_em
FROM agregado a
LEFT JOIN lakehouse_rotaperfume.gold.dim_vendedor v ON v.vendedor_id = a.vendedor_id;

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor IS
  'Mart para a diretoria comercial. Grão: vendedor x mês. Conforma com fato_vendas (mesma receita/margem agregadas).';

ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN atingimento COMMENT
  'Receita do mês dividida pela meta_mensal do vendedor. 1.0 = bateu a meta exatamente.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN ticket_medio COMMENT
  'Receita do mês dividida pelo número de pedidos distintos do vendedor no mês.';

-- produto -----------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_produto_performance AS
WITH mensal AS (
  SELECT sku, ano, mes,
    SUM(receita) AS receita,
    SUM(margem) AS margem,
    SUM(quantidade) AS quantidade
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY sku, ano, mes
),
totais_sku AS (
  SELECT sku, SUM(receita) AS receita_total
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY sku
),
curva AS (
  SELECT
    sku,
    SUM(receita_total) OVER (ORDER BY receita_total DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
      / SUM(receita_total) OVER () AS pct_acumulado
  FROM totais_sku
),
classificado AS (
  SELECT sku,
    CASE WHEN pct_acumulado <= 0.8 THEN 'A' WHEN pct_acumulado <= 0.95 THEN 'B' ELSE 'C' END AS curva_abc
  FROM curva
)
SELECT
  m.sku,
  pr.marca,
  pr.categoria,
  m.ano,
  m.mes,
  m.receita,
  m.margem,
  ROUND(100 * m.margem / NULLIF(m.receita, 0), 2) AS margem_pct,
  m.quantidade,
  c.curva_abc,
  current_timestamp() AS _processado_em
FROM mensal m
LEFT JOIN classificado c ON c.sku = m.sku
LEFT JOIN lakehouse_rotaperfume.gold.dim_produto pr ON pr.sku = m.sku;

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_produto_performance IS
  'Mart para a diretoria de produto. Grão: SKU x mês. Conforma com fato_vendas (mesma receita agregada — teste 8).';

ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN curva_abc COMMENT
  'Classificação ABC por receita ACUMULADA do SKU no período inteiro (não por mês): A até 80% da receita acumulada, B até 95%, C o resto. Mesma classificação repetida em todas as linhas do SKU.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN margem_pct COMMENT
  'Margem do mês dividida pela receita do mês, em percentual.';

-- financeiro ----------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento AS
SELECT
  year(data_vencimento) AS ano,
  month(data_vencimento) AS mes,
  SUM(valor) AS valor_a_receber,
  SUM(valor) FILTER (WHERE data_pagamento IS NOT NULL) AS recebido,
  AVG(datediff(data_pagamento, data_vencimento))
    FILTER (WHERE data_pagamento IS NOT NULL AND data_pagamento > data_vencimento) AS atraso_medio_dias,
  SUM(valor - valor_liquido) AS custo_taxa,
  current_timestamp() AS _processado_em
FROM lakehouse_rotaperfume.silver.pagamentos
GROUP BY year(data_vencimento), month(data_vencimento);

COMMENT ON TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento IS
  'Mart para a diretoria financeira. Grão: mês de vencimento do pagamento. Não conforma com fato_vendas — reflete o ciclo de pagamento, não o de venda.';

ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN atraso_medio_dias COMMENT
  'Média de dias entre vencimento e pagamento, só para pagamentos feitos em atraso (data_pagamento > data_vencimento). NULL no mês sem nenhum pagamento atrasado.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN custo_taxa COMMENT
  'Soma de (valor - valor_liquido): o custo da taxa de meio de pagamento, independente de já ter sido recebido.';
