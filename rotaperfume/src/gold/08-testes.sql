-- 12 testes de qualidade. Teste que não quebra o job não é teste, é relatório:
-- a 1ª instrução monta a tabela de resultados (imprime nome, calculado,
-- esperado, passou/falhou de TODOS os 12, mesmo que algum tenha falhado); a
-- 2ª instrução é que derruba o job com raise_error se qualquer um falhou —
-- sem essa separação, o primeiro teste que falha esconderia os outros 8.
-- Se um teste falhar, a correção é na transformação — nunca no teste.

CREATE OR REPLACE TEMPORARY VIEW resultados_testes AS

SELECT 1 AS teste, 'receita_gold_igual_silver' AS nome,
  CAST(receita_gold AS STRING) AS valor_calculado, CAST(receita_silver AS STRING) AS valor_esperado,
  ABS(receita_gold - receita_silver) <= 0.01 AS passou
FROM (
  SELECT
    (SELECT ROUND(SUM(receita), 2) FROM lakehouse_rotaperfume.gold.fato_vendas) AS receita_gold,
    (SELECT ROUND(SUM(valor_liquido), 2) FROM lakehouse_rotaperfume.silver.pedidos) AS receita_silver
)

UNION ALL

SELECT 2, 'cnpj_unico_em_silver_clientes',
  CAST(total AS STRING), CAST(unicos AS STRING),
  total = unicos
FROM (
  SELECT COUNT(*) AS total, COUNT(DISTINCT cnpj) AS unicos FROM lakehouse_rotaperfume.silver.clientes
)

UNION ALL

SELECT 3, 'data_pedido_nao_nula_em_silver_pedidos',
  CAST(nulos AS STRING), '0',
  nulos = 0
FROM (
  SELECT COUNT(*) AS nulos FROM lakehouse_rotaperfume.silver.pedidos WHERE data_pedido IS NULL
)

UNION ALL

SELECT 4, 'receita_negativa_so_em_devolucao',
  CAST(invalidas AS STRING), '0',
  invalidas = 0
FROM (
  SELECT COUNT(*) AS invalidas FROM lakehouse_rotaperfume.gold.fato_vendas WHERE receita < 0 AND NOT devolucao
)

UNION ALL

SELECT 5, 'volume_fato_vendas_dentro_do_esperado',
  CAST(linhas AS STRING), '140000 a 250000',
  linhas BETWEEN 140000 AND 250000
FROM (
  SELECT COUNT(*) AS linhas FROM lakehouse_rotaperfume.gold.fato_vendas
)

UNION ALL

SELECT 6, 'todo_pedido_id_do_fato_existe_na_silver',
  CAST(orfaos AS STRING), '0',
  orfaos = 0
FROM (
  SELECT COUNT(*) AS orfaos
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  LEFT JOIN lakehouse_rotaperfume.silver.pedidos p ON p.pedido_id = f.pedido_id
  WHERE p.pedido_id IS NULL
)

UNION ALL

SELECT 7, 'todo_cliente_id_do_fato_existe_na_silver',
  CAST(orfaos AS STRING), '0',
  orfaos = 0
FROM (
  SELECT COUNT(*) AS orfaos
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  LEFT JOIN lakehouse_rotaperfume.silver.clientes c ON c.cliente_id = f.cliente_id
  WHERE c.cliente_id IS NULL
)

UNION ALL

SELECT 8, 'mart_produto_performance_conforma_com_fato',
  CAST(receita_mart AS STRING), CAST(receita_fato AS STRING),
  ABS(receita_mart - receita_fato) <= 0.01
FROM (
  SELECT
    (SELECT ROUND(SUM(receita), 2) FROM lakehouse_rotaperfume.gold.mart_produto_performance) AS receita_mart,
    (SELECT ROUND(SUM(receita), 2) FROM lakehouse_rotaperfume.gold.fato_vendas) AS receita_fato
)

UNION ALL

SELECT 9, 'todo_cnpj_com_14_digitos',
  CAST(invalidos AS STRING), '0',
  invalidos = 0
FROM (
  SELECT COUNT(*) AS invalidos FROM lakehouse_rotaperfume.silver.clientes WHERE length(cnpj) <> 14
)

UNION ALL

-- a "auditoria de metadado": retorno_ligacao é a única tabela do projeto com
-- exigência de COMMENT em toda coluna sem exceção (ela não vem do pipeline,
-- então o metadado é a única documentação que sobra para quem for lê-la).
-- Escopado só a ela — as tabelas mais antigas (05 a 07) comentam apenas as
-- colunas não óbvias, e estender esta regra a todo o schema gold quebraria
-- o job por um padrão que elas nunca seguiram.
SELECT 10, 'retorno_ligacao_todas_colunas_com_comment',
  CAST(sem_comment AS STRING), '0',
  sem_comment = 0
FROM (
  SELECT COUNT(*) AS sem_comment
  FROM lakehouse_rotaperfume.information_schema.columns
  WHERE table_schema = 'gold' AND table_name = 'retorno_ligacao'
    AND (comment IS NULL OR comment = '')
)

UNION ALL

SELECT 11, 'ranking_marcas_conforma_com_fato',
  CAST(receita_ranking AS STRING), CAST(receita_fato AS STRING),
  ABS(receita_ranking - receita_fato) <= 0.01
FROM (
  SELECT
    (SELECT ROUND(SUM(receita), 2) FROM lakehouse_rotaperfume.gold.ranking_marcas) AS receita_ranking,
    (SELECT ROUND(SUM(receita), 2) FROM lakehouse_rotaperfume.gold.fato_vendas) AS receita_fato
)

UNION ALL

SELECT 12, 'receita_mensal_conforma_com_fato',
  CAST(receita_mensal AS STRING), CAST(receita_fato AS STRING),
  ABS(receita_mensal - receita_fato) <= 0.01
FROM (
  SELECT
    (SELECT ROUND(SUM(receita), 2) FROM lakehouse_rotaperfume.gold.receita_mensal) AS receita_mensal,
    (SELECT ROUND(SUM(receita), 2) FROM lakehouse_rotaperfume.gold.fato_vendas) AS receita_fato
);

SELECT * FROM resultados_testes ORDER BY teste;

SELECT
  CASE
    WHEN (SELECT COUNT(*) FROM resultados_testes WHERE NOT passou) = 0
    THEN 'TODOS OS 12 TESTES PASSARAM'
    ELSE raise_error((
      SELECT concat_ws('; ',
        collect_list(concat('teste ', CAST(teste AS STRING), ' (', nome, ') falhou: calculado=', valor_calculado, ' esperado=', valor_esperado))
      )
      FROM resultados_testes
      WHERE NOT passou
    ))
  END AS status_final;
