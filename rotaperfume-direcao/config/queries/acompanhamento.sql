-- Por vendedor: quantos estão na fila, quantos já foram trabalhados
-- (têm retorno registrado) e a contagem por status. status_retorno usa o
-- registro mais recente por cliente, mesmo critério de fila.sql.
WITH retorno_recente AS (
  SELECT cliente_id, status,
         ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY registrado_em DESC) AS rn
  FROM lakehouse_rotaperfume.gold.retorno_ligacao
)
SELECT
  f.vendedor,
  COUNT(*) AS na_fila,
  COUNT(r.status) AS trabalhados,
  SUM(CASE WHEN r.status = 'vendeu' THEN 1 ELSE 0 END) AS vendeu,
  SUM(CASE WHEN r.status = 'vai_pensar' THEN 1 ELSE 0 END) AS vai_pensar,
  SUM(CASE WHEN r.status = 'sem_interesse' THEN 1 ELSE 0 END) AS sem_interesse,
  SUM(CASE WHEN r.status = 'nao_atendeu' THEN 1 ELSE 0 END) AS nao_atendeu
FROM lakehouse_rotaperfume.gold.fila_semanal f
LEFT JOIN retorno_recente r ON r.cliente_id = f.cliente_id AND r.rn = 1
GROUP BY f.vendedor
ORDER BY f.vendedor;
