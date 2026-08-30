-- Silver → Gold: quatro dimensões conformadas, lidas só de silver.
-- Um cliente/produto/vendedor/dia aqui é sempre a mesma linha, não importa
-- qual mart ou fato a consulte depois.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_cliente AS
WITH pedidos_cliente AS (
  SELECT
    cliente_id,
    MIN(data_pedido) AS data_primeiro_pedido,
    MAX(data_pedido) AS data_ultimo_pedido,
    COUNT(*) AS total_pedidos,
    SUM(valor_liquido) AS receita_acumulada
  FROM lakehouse_rotaperfume.silver.pedidos
  WHERE NOT cancelado
  GROUP BY cliente_id
)
SELECT
  c.cliente_id,
  c.razao_social,
  c.segmento,
  c.cidade,
  c.uf,
  c.data_cadastro,
  pc.data_primeiro_pedido,
  pc.data_ultimo_pedido,
  coalesce(pc.total_pedidos, 0) AS total_pedidos,
  coalesce(pc.receita_acumulada, CAST(0 AS DECIMAL(18,2))) AS receita_acumulada,
  datediff(current_date(), pc.data_ultimo_pedido) AS dias_sem_comprar,
  current_timestamp() AS _processado_em
FROM lakehouse_rotaperfume.silver.clientes c
LEFT JOIN pedidos_cliente pc ON pc.cliente_id = c.cliente_id;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_cliente IS
  'Dimensão conformada de cliente: uma linha por cliente, com histórico de compras agregado (pedidos não cancelados).';

ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN receita_acumulada COMMENT
  'Soma de valor_liquido dos pedidos não cancelados do cliente — 0 para cliente sem pedido, não NULL.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN dias_sem_comprar COMMENT
  'Dias corridos desde o último pedido não cancelado até hoje. NULL para cliente que nunca comprou.';

-- produto ---------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_produto AS
SELECT
  sku,
  descricao,
  categoria,
  marca,
  nota_olfativa,
  custo_unitario,
  preco_tabela,
  data_lancamento,
  NOT ativo AS descontinuado,
  current_timestamp() AS _processado_em
FROM lakehouse_rotaperfume.silver.produtos;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_produto IS
  'Dimensão conformada de produto: uma linha por SKU.';

ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN descontinuado COMMENT
  'true quando o produto não está mais ativo no catálogo (NOT ativo) — usar para marcar SKU descontinuado em qualquer mart.';

-- vendedor --------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_vendedor AS
SELECT
  vendedor_id,
  nome,
  regiao,
  meta_mensal,
  data_desligamento IS NULL AS ativo,
  current_timestamp() AS _processado_em
FROM lakehouse_rotaperfume.silver.vendedores;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_vendedor IS
  'Dimensão conformada de vendedor: uma linha por vendedor.';

ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN ativo COMMENT
  'true quando o vendedor não tem data_desligamento — ainda está na empresa.';

-- calendário --------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_calendario AS
WITH limites AS (
  SELECT MIN(data_pedido) AS data_min, MAX(data_pedido) AS data_max
  FROM lakehouse_rotaperfume.silver.pedidos
),
dias AS (
  SELECT explode(sequence(data_min, data_max, interval 1 day)) AS data
  FROM limites
)
SELECT
  data,
  year(data) AS ano,
  month(data) AS mes,
  CASE month(data)
    WHEN 1 THEN 'Janeiro' WHEN 2 THEN 'Fevereiro' WHEN 3 THEN 'Março'
    WHEN 4 THEN 'Abril' WHEN 5 THEN 'Maio' WHEN 6 THEN 'Junho'
    WHEN 7 THEN 'Julho' WHEN 8 THEN 'Agosto' WHEN 9 THEN 'Setembro'
    WHEN 10 THEN 'Outubro' WHEN 11 THEN 'Novembro' WHEN 12 THEN 'Dezembro'
  END AS nome_mes,
  quarter(data) AS trimestre,
  CASE dayofweek(data)
    WHEN 1 THEN 'Domingo' WHEN 2 THEN 'Segunda-feira' WHEN 3 THEN 'Terça-feira'
    WHEN 4 THEN 'Quarta-feira' WHEN 5 THEN 'Quinta-feira' WHEN 6 THEN 'Sexta-feira'
    WHEN 7 THEN 'Sábado'
  END AS dia_semana,
  month(data) IN (4, 6, 10) AS mes_pico_setor,
  current_timestamp() AS _processado_em
FROM dias;

COMMENT ON TABLE lakehouse_rotaperfume.gold.dim_calendario IS
  'Uma linha por dia, cobrindo do primeiro ao último data_pedido em silver.pedidos (calculado dinamicamente, não fixo).';

ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN mes_pico_setor COMMENT
  'true em abril, junho e outubro — meses de pico de vendas do setor de perfumaria, definição de negócio.';
