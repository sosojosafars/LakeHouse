-- Alimenta o Select de filtro de "A semana": um vendedor por linha, com
-- quantos contatos ele tem na fila desta semana.
SELECT vendedor, COUNT(*) AS contatos
FROM lakehouse_rotaperfume.gold.fila_semanal
GROUP BY vendedor
ORDER BY contatos DESC;
