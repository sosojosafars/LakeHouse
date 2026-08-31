-- Os quatro números do topo de "A semana": contatos/vendedores/receita
-- esperada da fila atual, acertos/lift/taxa_base da última versão do
-- modelo, e quantas ligações já foram registradas (e quantas viraram
-- pedido) em gold.retorno_ligacao. Sem parâmetro — não depende do filtro
-- de vendedor da tela.
SELECT
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fila_semanal) AS contatos,
  (SELECT COUNT(DISTINCT vendedor) FROM lakehouse_rotaperfume.gold.fila_semanal) AS vendedores,
  (SELECT ROUND(SUM(score * ticket_medio), 2) FROM lakehouse_rotaperfume.gold.fila_semanal) AS receita_esperada,
  (SELECT MAX(_processado_em) FROM lakehouse_rotaperfume.gold.fila_semanal) AS referencia_fila,
  m.acertos_top200,
  m.lift_top200,
  m.taxa_base,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.retorno_ligacao) AS ligacoes_registradas,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.retorno_ligacao WHERE status = 'vendeu') AS viraram_pedido
FROM lakehouse_rotaperfume.gold.modelo_metricas m
QUALIFY ROW_NUMBER() OVER (ORDER BY m.versao DESC) = 1;
