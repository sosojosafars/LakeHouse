-- CONTRATO DE fato_vendas — escrito antes do SQL.
-- Granularidade: uma linha por ITEM de pedido (item_id).
-- Filtro: exclui pedidos cancelados (silver.pedidos.cancelado). NÃO exclui
--   devolução — devolução entra com quantidade e receita NEGATIVAS,
--   sinalizada em devolucao.
-- Dimensões: data_pedido, ano, mes, canal, cliente_id, razao_social,
--   segmento, cidade, vendedor_id, sku, categoria, marca, nota_olfativa.
-- Métricas: quantidade, preco_praticado, receita, custo, margem, devolucao.
--   custo  = quantidade (com sinal) * custo_unitario do produto.
--   margem = receita - custo.
-- Por que a devolução fica DENTRO: se ficasse fora, esta tabela somaria mais
-- que silver.pedidos — a mesma pergunta ("qual é o faturamento?") daria dois
-- números diferentes em duas camadas do mesmo pipeline. Quem quiser o bruto
-- (sem devolução) filtra com: SUM(receita) FILTER (WHERE NOT devolucao).

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.fato_vendas
PARTITIONED BY (ano, mes)
AS
WITH mapa_cliente AS (
  -- 40 CNPJs foram deduplicados em silver.clientes (ver cliente_ids_duplicados);
  -- pedidos antigos ainda referenciam o cliente_id descartado. Sem este mapa,
  -- essas linhas ficam com um cliente_id que não existe em silver.clientes —
  -- é exatamente o que o teste 7 (integridade referencial) pegou.
  SELECT
    explode(cliente_ids_duplicados) AS cliente_id_descartado,
    cliente_id AS cliente_id_canonico
  FROM lakehouse_rotaperfume.silver.clientes
  WHERE cliente_ids_duplicados IS NOT NULL
),
base AS (
  SELECT
    i.item_id,
    i.pedido_id,
    p.data_pedido,
    p.ano,
    p.mes,
    p.canal,
    coalesce(mc.cliente_id_canonico, p.cliente_id) AS cliente_id,
    c.razao_social,
    c.segmento,
    c.cidade,
    p.vendedor_id,
    i.sku,
    pr.categoria,
    pr.marca,
    pr.nota_olfativa,
    CASE WHEN i.devolucao THEN -i.quantidade_abs ELSE i.quantidade_abs END AS quantidade,
    i.preco_praticado,
    i.valor_bruto AS receita,
    pr.custo_unitario,
    i.devolucao
  FROM lakehouse_rotaperfume.silver.itens_pedido i
  JOIN lakehouse_rotaperfume.silver.pedidos  p  ON p.pedido_id = i.pedido_id
  JOIN lakehouse_rotaperfume.silver.produtos pr ON pr.sku = i.sku
  LEFT JOIN mapa_cliente mc ON mc.cliente_id_descartado = p.cliente_id
  LEFT JOIN lakehouse_rotaperfume.silver.clientes c ON c.cliente_id = coalesce(mc.cliente_id_canonico, p.cliente_id)
  WHERE NOT p.cancelado
)
SELECT
  item_id,
  pedido_id,
  data_pedido,
  ano,
  mes,
  canal,
  cliente_id,
  razao_social,
  segmento,
  cidade,
  vendedor_id,
  sku,
  categoria,
  marca,
  nota_olfativa,
  quantidade,
  preco_praticado,
  receita,
  quantidade * custo_unitario AS custo,
  receita - (quantidade * custo_unitario) AS margem,
  devolucao,
  current_timestamp() AS _processado_em
FROM base;

COMMENT ON TABLE lakehouse_rotaperfume.gold.fato_vendas IS
  'Fato único de vendas, grão = item de pedido. Único lugar da gold onde a regra de margem é escrita. Exclui pedidos cancelados; inclui devolução (com sinal negativo).';

ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN item_id COMMENT
  'Identificador do item de pedido de origem — o grão desta tabela.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN pedido_id COMMENT
  'Pedido ao qual este item pertence. Todo pedido_id aqui existe em silver.pedidos (não cancelado).';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN data_pedido COMMENT
  'Data em que o pedido foi feito, herdada de silver.pedidos.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN ano COMMENT
  'Ano do pedido — usado como chave de particionamento da tabela.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN mes COMMENT
  'Mês do pedido — usado como chave de particionamento da tabela.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN canal COMMENT
  'Canal de venda do pedido (ex.: loja física, e-commerce, representante).';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN cliente_id COMMENT
  'Cliente do pedido, já remapeado para o cliente_id canônico quando o pedido referenciava um cadastro descartado na deduplicação da silver (ver silver.clientes.cliente_ids_duplicados). Todo cliente_id aqui existe em silver.clientes.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN razao_social COMMENT
  'Razão social do cliente no momento do processamento, desnormalizada da dimensão para consulta direta sem JOIN.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN segmento COMMENT
  'Segmento de mercado do cliente, desnormalizado da dimensão.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN cidade COMMENT
  'Cidade do cliente, desnormalizada da dimensão.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN vendedor_id COMMENT
  'Vendedor responsável pelo pedido.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN sku COMMENT
  'Produto do item, desnormalizado nas colunas categoria/marca/nota_olfativa a seguir.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN categoria COMMENT
  'Categoria do produto no momento do processamento.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN marca COMMENT
  'Marca do produto no momento do processamento.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN nota_olfativa COMMENT
  'Nota olfativa do produto no momento do processamento.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN quantidade COMMENT
  'Quantidade COM SINAL: positiva em venda, negativa em devolução (ver coluna devolucao). Nunca use quantidade_abs aqui — o sinal é o que faz a soma bater com a silver.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN preco_praticado COMMENT
  'Preço unitário praticado no item, sem sinal.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN receita COMMENT
  'Receita do item, COM devolução (negativa quando devolucao = true). Para o bruto vendido, sem devolução: SUM(receita) FILTER (WHERE NOT devolucao).';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN custo COMMENT
  'Quantidade (com sinal) vezes o custo_unitario do produto. Negativo em devolução, simetricamente à receita.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN margem COMMENT
  'Receita menos custo do produto. Não considera desconto comercial nem frete.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN devolucao COMMENT
  'true quando este item é uma devolução (quantidade/receita/custo negativos), herdado de silver.itens_pedido.';
