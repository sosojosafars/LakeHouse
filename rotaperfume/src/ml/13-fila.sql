-- gold.fila_semanal — os 200 contatos da semana, uma linha por cliente
-- selecionado, com motivo e sugestão em português.
--
-- A ORDEM DAS OPERAÇÕES IMPORTA: filtra vendedor elegível (carteira vigente,
-- vendedor não desligado) ANTES do ORDER BY score DESC LIMIT 200 — se o
-- filtro vier depois do LIMIT, seis vendedores desligados levam os clientes
-- deles junto e a fila sai com menos de 200 linhas (o teste 1 pega isso).
-- Fila é global (ORDER BY score DESC LIMIT 200), capacidade é por vendedor:
-- não há cota igual por vendedor, senão a carteira quente de um obriga a
-- gastar ligação com cliente frio da carteira de outro.
--
-- "hoje" deste dataset é 2026-08-31 (mesma âncora do prompt 1) — nunca
-- current_date().
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.fila_semanal
AS
WITH elegiveis AS (
  SELECT CAST(c.cliente_id AS INT) AS cliente_id, c.vendedor_id
  FROM lakehouse_rotaperfume.silver.carteira c
  WHERE c.vigente AND NOT c.orfao_vendedor_desligado
),
top200 AS (
  SELECT e.cliente_id, e.vendedor_id, s.score, s.faixa
  FROM elegiveis e
  JOIN lakehouse_rotaperfume.gold.score_propensao s ON s.cliente_id = e.cliente_id
  ORDER BY s.score DESC
  LIMIT 200
),
base AS (
  SELECT
    t.cliente_id, t.vendedor_id, t.score, t.faixa,
    ROW_NUMBER() OVER (PARTITION BY t.vendedor_id ORDER BY t.score DESC) AS ordem,
    f.atraso_relativo, f.intervalo_medio_dias, f.recencia_dias,
    f.comprou_lancamento, f.valor_total, f.ticket_medio,
    -- corte de "cliente grande" medido no proprio grupo dos 200 selecionados
    PERCENTILE_APPROX(f.valor_total, 0.9) OVER () AS p90_valor_total
  FROM top200 t
  JOIN lakehouse_rotaperfume.gold.features_cliente f ON CAST(f.cliente_id AS INT) = t.cliente_id
),
marca_preferida AS (
  -- marca de maior receita historica do cliente, só para os 200 da fila
  SELECT f.cliente_id, f.marca,
         ROW_NUMBER() OVER (PARTITION BY f.cliente_id ORDER BY SUM(f.receita) DESC) AS rn
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  JOIN base b ON CAST(f.cliente_id AS INT) = b.cliente_id
  GROUP BY f.cliente_id, f.marca
),
sku_candidato AS (
  -- SKUs da marca preferida que o cliente já comprou, com a data da última compra
  SELECT f.cliente_id, f.sku, SUM(f.quantidade) AS qtd_total, MAX(f.data_pedido) AS ultima_compra
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  JOIN marca_preferida mp ON mp.rn = 1 AND CAST(f.cliente_id AS INT) = mp.cliente_id AND f.marca = mp.marca
  GROUP BY f.cliente_id, f.sku
),
estoque_recente AS (
  SELECT sku, saldo
  FROM (
    SELECT sku, saldo, ROW_NUMBER() OVER (PARTITION BY sku ORDER BY data_snapshot DESC) AS rn
    FROM lakehouse_rotaperfume.silver.estoque
  ) ultimo
  WHERE ultimo.rn = 1
),
sugestoes AS (
  -- o SKU mais comprado historicamente na marca preferida, ENTRE os que o
  -- cliente nao comprou nos ultimos 90 dias
  SELECT sc.cliente_id,
         concat(
           'Sugestao: ', sc.sku, ', ', FORMAT_NUMBER(sc.qtd_total, 0), ' unidades compradas no historico. ',
           'Estoque atual: ', COALESCE(CAST(er.saldo AS STRING), '0'), ' un.'
         ) AS sugestao
  FROM (
    SELECT cliente_id, sku, qtd_total,
           ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY qtd_total DESC) AS rn
    FROM sku_candidato
    WHERE ultima_compra < DATE_SUB(DATE'2026-08-31', 90)
  ) sc
  LEFT JOIN estoque_recente er ON er.sku = sc.sku
  WHERE sc.rn = 1
)
SELECT
  v.nome AS vendedor,
  b.ordem,
  b.cliente_id,
  c.razao_social,
  c.cidade,
  c.uf,
  b.score,
  b.faixa,
  b.ticket_medio,
  -- ordem medida contra os 200 reais deste workspace, nao a ordem "natural":
  -- comprou_lancamento é verdadeiro para a maioria (146/200 depois de tirar
  -- atraso e valor_total) — se checado antes de valor_total, ele "come" quase
  -- tudo (174/200) e o resto vira sinal genérico demais para o vendedor confiar
  CASE
    WHEN b.atraso_relativo > 3 THEN concat(
      'Compra a cada ', FORMAT_NUMBER(b.intervalo_medio_dias, 0), ' dias e esta ha ',
      FORMAT_NUMBER(b.recencia_dias, 0), ' dias sem pedido. Risco de perder para o concorrente.'
    )
    WHEN b.atraso_relativo > 1.5 THEN concat(
      'Esta ', FORMAT_NUMBER(b.atraso_relativo, 1), ' vezes mais atrasado que o proprio ritmo de compra.'
    )
    WHEN b.valor_total >= b.p90_valor_total THEN concat(
      -- REPLACE: FORMAT_NUMBER usa virgula como separador de milhar (padrao
      -- americano) — em portugues isso le como "cento e noventa e seis
      -- virgula setecentos e quarenta e dois", nao "196 mil"
      'Cliente grande: R$ ', REPLACE(FORMAT_NUMBER(b.valor_total, 0), ',', '.'), ' em compras no historico. Manter proximo.'
    )
    WHEN b.comprou_lancamento = 1 THEN
      'Comprou lancamento recente. Alta chance de repetir a compra.'
    ELSE 'Dentro do ritmo normal de compra. Contato de manutencao.'
  END AS motivo,
  sg.sugestao,
  current_timestamp() AS _processado_em
FROM base b
JOIN lakehouse_rotaperfume.gold.dim_cliente c ON CAST(c.cliente_id AS INT) = b.cliente_id
JOIN lakehouse_rotaperfume.gold.dim_vendedor v ON v.vendedor_id = b.vendedor_id
LEFT JOIN sugestoes sg ON sg.cliente_id = b.cliente_id;

COMMENT ON TABLE lakehouse_rotaperfume.gold.fila_semanal IS
  'As 200 ligações da semana: cliente com maior score de propensão dentro da carteira elegível de cada vendedor (vigente, vendedor não desligado), com motivo em português e sugestão de produto. Gerada por src/ml/13-fila.sql a partir de gold.score_propensao.';

ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN vendedor COMMENT
  'Nome do vendedor responsável pela ligação, de gold.dim_vendedor.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN ordem COMMENT
  'Posição do cliente na fila DESTE vendedor, por score decrescente (1 = prioridade máxima). Não é a posição na fila geral de 200.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN cliente_id COMMENT
  'Cliente selecionado para contato esta semana.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN razao_social COMMENT
  'Razão social do cliente, de gold.dim_cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN cidade COMMENT
  'Cidade do cliente, de gold.dim_cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN uf COMMENT
  'UF do cliente, de gold.dim_cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN score COMMENT
  'Score de propensão de compra em 7 dias (0 a 1), de gold.score_propensao.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN faixa COMMENT
  'Faixa do score (Fria/Morna/Quente/Muito quente), de gold.score_propensao.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN ticket_medio COMMENT
  'Ticket médio histórico do cliente, de gold.features_cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN motivo COMMENT
  'Explicação em português de por que este cliente está na fila, com os números reais dele. Nunca nulo — é o que o vendedor lê antes de ligar, e o que o Genie usa para responder "por que" sem inventar.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN sugestao COMMENT
  'SKU mais comprado historicamente na marca preferida do cliente, entre os que ele não comprou nos últimos 90 dias, com o saldo do snapshot mais recente de estoque. Pode ser NULL (cliente sem histórico de marca com SKU recorrente).';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN _processado_em COMMENT
  'Timestamp de quando esta fila foi gerada.';

-- Funções SQL do agente -------------------------------------------------------
-- Todo parâmetro prefixado com p_: parâmetro com o mesmo nome de uma coluna
-- fica ambíguo dentro do corpo da função e o CREATE falha.

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.priorizar_carteira(p_vendedor STRING, p_quantos INT)
RETURNS TABLE (
  ordem INT, cliente_id INT, razao_social STRING, cidade STRING,
  score DOUBLE, faixa STRING, motivo STRING, sugestao STRING
)
COMMENT 'Devolve os p_quantos clientes de maior prioridade na carteira do vendedor p_vendedor, em ordem. Use quando o vendedor perguntar "quem eu ligo essa semana" ou pedir sua lista priorizada.'
RETURN
  -- ordem <= p_quantos, NAO "LIMIT p_quantos": Databricks exige LIMIT
  -- constante (INVALID_LIMIT_LIKE_EXPRESSION) — a fila já vem numerada
  SELECT ordem, cliente_id, razao_social, cidade, score, faixa, motivo, sugestao
  FROM lakehouse_rotaperfume.gold.fila_semanal
  WHERE vendedor = p_vendedor AND ordem <= p_quantos
  ORDER BY ordem;

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.contexto_cliente(p_cliente_id INT)
RETURNS TABLE (
  razao_social STRING, cidade STRING, uf STRING,
  total_pedidos BIGINT, receita_acumulada DECIMAL(28, 2), dias_sem_comprar INT,
  ticket_medio DOUBLE, marca_preferida STRING, ultima_compra DATE
)
COMMENT 'Histórico do cliente p_cliente_id: total de pedidos, receita acumulada, dias sem comprar, ticket médio, marca preferida e data da última compra. Use quando o vendedor perguntar sobre o histórico ou perfil de um cliente antes de ligar.'
RETURN
  SELECT
    c.razao_social, c.cidade, c.uf,
    c.total_pedidos, c.receita_acumulada, c.dias_sem_comprar,
    f.ticket_medio,
    (
      -- subquery escalar correlacionada precisa ser agregada (MAX_BY), nao
      -- ROW_NUMBER()+WHERE rn=1: UNSUPPORTED_SUBQUERY_EXPRESSION_CATEGORY
      SELECT MAX_BY(mp.marca, mp.receita_total) FROM (
        SELECT marca, SUM(receita) AS receita_total
        FROM lakehouse_rotaperfume.gold.fato_vendas
        WHERE CAST(cliente_id AS INT) = p_cliente_id
        GROUP BY marca
      ) mp
    ) AS marca_preferida,
    c.data_ultimo_pedido AS ultima_compra
  FROM lakehouse_rotaperfume.gold.dim_cliente c
  LEFT JOIN lakehouse_rotaperfume.gold.features_cliente f ON CAST(f.cliente_id AS INT) = p_cliente_id
  WHERE CAST(c.cliente_id AS INT) = p_cliente_id;

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.sugerir_produtos(p_cliente_id INT)
RETURNS TABLE (sku STRING, marca STRING, categoria STRING, ultima_compra DATE, saldo INT)
COMMENT 'SKUs que o cliente p_cliente_id costumava comprar e parou de comprar nos últimos 90 dias, com o saldo em estoque de cada um. Use quando o vendedor perguntar o que oferecer para um cliente.'
RETURN
  SELECT h.sku, h.marca, h.categoria, h.ultima_compra, e.saldo
  FROM (
    SELECT f.sku, f.marca, f.categoria, MAX(f.data_pedido) AS ultima_compra
    FROM lakehouse_rotaperfume.gold.fato_vendas f
    WHERE CAST(f.cliente_id AS INT) = p_cliente_id
    GROUP BY f.sku, f.marca, f.categoria
    HAVING MAX(f.data_pedido) < DATE_SUB(DATE'2026-08-31', 90)
  ) h
  LEFT JOIN (
    SELECT sku, saldo
    FROM (
      SELECT sku, saldo, ROW_NUMBER() OVER (PARTITION BY sku ORDER BY data_snapshot DESC) AS rn
      FROM lakehouse_rotaperfume.silver.estoque
    ) ultimo
    WHERE ultimo.rn = 1
  ) e ON e.sku = h.sku
  ORDER BY h.ultima_compra ASC;

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.checar_disponibilidade(p_sku STRING)
RETURNS TABLE (sku STRING, data_snapshot DATE, saldo INT, ruptura BOOLEAN)
COMMENT 'Saldo e ruptura do SKU p_sku no snapshot mais recente de estoque. Use quando o vendedor perguntar se um produto tem disponibilidade antes de prometer prazo.'
RETURN
  SELECT sku, data_snapshot, saldo, ruptura
  FROM lakehouse_rotaperfume.silver.estoque
  WHERE sku = p_sku
  ORDER BY data_snapshot DESC
  LIMIT 1;

-- 3 testes que derrubam a tarefa -----------------------------------------------
-- mesmo padrão de src/gold/08-testes.sql: a 1ª instrução mostra todos os
-- resultados mesmo se algum falhar; a 2ª derruba o job com raise_error.

CREATE OR REPLACE TEMPORARY VIEW resultados_testes_fila AS

SELECT 1 AS teste, 'fila_tem_200_linhas' AS nome,
  CAST(linhas AS STRING) AS valor_calculado, '200' AS valor_esperado,
  linhas = 200 AS passou
FROM (SELECT COUNT(*) AS linhas FROM lakehouse_rotaperfume.gold.fila_semanal)

UNION ALL

SELECT 2, 'motivo_nunca_nulo_ou_vazio',
  CAST(invalidos AS STRING), '0',
  invalidos = 0
FROM (
  SELECT COUNT(*) AS invalidos FROM lakehouse_rotaperfume.gold.fila_semanal
  WHERE motivo IS NULL OR TRIM(motivo) = ''
)

UNION ALL

SELECT 3, 'score_dentro_do_intervalo_0_1',
  CAST(fora AS STRING), '0',
  fora = 0
FROM (
  SELECT COUNT(*) AS fora FROM lakehouse_rotaperfume.gold.fila_semanal
  WHERE score < 0 OR score > 1
);

SELECT * FROM resultados_testes_fila ORDER BY teste;

SELECT
  CASE
    WHEN (SELECT COUNT(*) FROM resultados_testes_fila WHERE NOT passou) = 0
    THEN 'TODOS OS 3 TESTES PASSARAM'
    ELSE raise_error((
      SELECT concat_ws('; ',
        collect_list(concat('teste ', CAST(teste AS STRING), ' (', nome, ') falhou: calculado=', valor_calculado, ' esperado=', valor_esperado))
      )
      FROM resultados_testes_fila
      WHERE NOT passou
    ))
  END AS status_final;
