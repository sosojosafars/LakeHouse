-- @param vendedor STRING Todos
-- Os 200 contatos com tudo que o vendedor lê antes de ligar. 'Todos' não
-- filtra — é o valor selecionado por padrão no filtro da tela.
WITH retorno_recente AS (
  SELECT cliente_id, status, comentario,
         ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY registrado_em DESC) AS rn
  FROM lakehouse_rotaperfume.gold.retorno_ligacao
)
SELECT
  f.vendedor,
  f.ordem,
  f.cliente_id,
  f.razao_social,
  f.cidade,
  f.uf,
  f.ticket_medio,
  f.score,
  f.faixa,
  f.motivo,
  f.sugestao,
  DATE(f._processado_em) AS referencia_fila,
  r.status AS status_retorno,
  r.comentario AS comentario_retorno
FROM lakehouse_rotaperfume.gold.fila_semanal f
LEFT JOIN retorno_recente r ON r.cliente_id = f.cliente_id AND r.rn = 1
WHERE :vendedor = 'Todos' OR f.vendedor = :vendedor
ORDER BY f.vendedor, f.ordem;
