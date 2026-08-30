-- Silver: vendedores, carteira, oportunidades, visitas, pagamentos, estoque.
-- carteira e oportunidades EXPÕEM problemas do dado (vendedor desligado com
-- carteira vigente; nomenclatura real das etapas) em vez de escondê-los.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.vendedores AS
WITH base AS (
  SELECT *, COUNT(*) OVER () AS _linhas_origem
  FROM lakehouse_rotaperfume.bronze.vendedores
)
SELECT
  vendedor_id,
  nome,
  regiao,
  uf,
  coalesce(try_to_date(data_admissao), try_to_date(data_admissao, 'dd/MM/yyyy')) AS data_admissao,
  coalesce(try_to_date(data_desligamento), try_to_date(data_desligamento, 'dd/MM/yyyy')) AS data_desligamento,
  TRY_CAST(meta_mensal AS DECIMAL(18,2)) AS meta_mensal,
  current_timestamp() AS _processado_em,
  _linhas_origem
FROM base;

COMMENT ON TABLE lakehouse_rotaperfume.silver.vendedores IS
  'Vendedores tipados. data_desligamento NULL significa vendedor ainda ativo.';

ALTER TABLE lakehouse_rotaperfume.silver.vendedores ALTER COLUMN data_desligamento COMMENT
  'NULL quando o vendedor ainda está ativo — vazio na origem, preservado como NULL, não inventado.';

-- carteira ------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.carteira AS
WITH base AS (
  SELECT *, COUNT(*) OVER () AS _linhas_origem
  FROM lakehouse_rotaperfume.bronze.carteira
),
tipado AS (
  SELECT
    carteira_id,
    cliente_id,
    vendedor_id,
    coalesce(try_to_date(data_inicio), try_to_date(data_inicio, 'dd/MM/yyyy')) AS data_inicio,
    coalesce(try_to_date(data_fim), try_to_date(data_fim, 'dd/MM/yyyy')) AS data_fim,
    _linhas_origem
  FROM base
)
SELECT
  t.carteira_id,
  t.cliente_id,
  t.vendedor_id,
  t.data_inicio,
  t.data_fim,
  (t.data_fim IS NULL OR t.data_fim >= current_date())
    AND (v.data_desligamento IS NULL OR v.data_desligamento >= current_date()) AS vigente,
  (t.data_fim IS NULL OR t.data_fim >= current_date())
    AND v.data_desligamento IS NOT NULL AND v.data_desligamento < current_date() AS orfao_vendedor_desligado,
  current_timestamp() AS _processado_em,
  t._linhas_origem
FROM tipado t
LEFT JOIN lakehouse_rotaperfume.silver.vendedores v ON t.vendedor_id = v.vendedor_id;

COMMENT ON TABLE lakehouse_rotaperfume.silver.carteira IS
  'Carteira de clientes por vendedor. vigente cruza data_fim da carteira com o desligamento do vendedor; orfao_vendedor_desligado expõe carteiras vigentes por data mas com vendedor já desligado — o dado não é corrigido, o problema é exposto para o gestor.';

ALTER TABLE lakehouse_rotaperfume.silver.carteira ALTER COLUMN vigente COMMENT
  'Respeita data_fim da carteira E data_desligamento do vendedor — não só uma das duas.';
ALTER TABLE lakehouse_rotaperfume.silver.carteira ALTER COLUMN orfao_vendedor_desligado COMMENT
  'true quando a carteira está vigente pela data_fim mas o vendedor responsável já foi desligado — problema de dado exposto, não corrigido.';

-- oportunidades ---------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.oportunidades AS
WITH base AS (
  SELECT *, COUNT(*) OVER () AS _linhas_origem
  FROM lakehouse_rotaperfume.bronze.oportunidades
)
SELECT
  oportunidade_id,
  cliente_id,
  vendedor_id,
  origem,
  coalesce(try_to_date(data_abertura), try_to_date(data_abertura, 'dd/MM/yyyy')) AS data_abertura,
  etapa,
  etapa IN ('Fechado ganho', 'Fechado perdido') AS fechada,
  etapa = 'Fechado ganho' AS ganha,
  TRY_CAST(probabilidade_pct AS INT) AS probabilidade_pct,
  TRY_CAST(valor_estimado AS DECIMAL(18,2)) AS valor_estimado,
  coalesce(try_to_date(data_fechamento), try_to_date(data_fechamento, 'dd/MM/yyyy')) AS data_fechamento,
  TRY_CAST(ciclo_dias AS INT) AS ciclo_dias,
  motivo_perda,
  current_timestamp() AS _processado_em,
  _linhas_origem
FROM base;

COMMENT ON TABLE lakehouse_rotaperfume.silver.oportunidades IS
  'Oportunidades tipadas.';

ALTER TABLE lakehouse_rotaperfume.silver.oportunidades ALTER COLUMN ganha COMMENT
  'etapa = ''Fechado ganho'' — a string exata confirmada na origem com SELECT DISTINCT etapa, não ''Ganha''.';
ALTER TABLE lakehouse_rotaperfume.silver.oportunidades ALTER COLUMN fechada COMMENT
  'etapa IN (''Fechado ganho'', ''Fechado perdido'') — as duas etapas terminais da origem.';

-- visitas ---------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.visitas AS
WITH base AS (
  SELECT *, COUNT(*) OVER () AS _linhas_origem
  FROM lakehouse_rotaperfume.bronze.visitas
)
SELECT
  visita_id,
  cliente_id,
  vendedor_id,
  coalesce(try_to_date(data_visita), try_to_date(data_visita, 'dd/MM/yyyy')) AS data_visita,
  resultado,
  TRY_CAST(duracao_min AS INT) AS duracao_min,
  current_timestamp() AS _processado_em,
  _linhas_origem
FROM base;

COMMENT ON TABLE lakehouse_rotaperfume.silver.visitas IS
  'Visitas tipadas: data convertida com try_to_date, duracao_min como INT.';

-- pagamentos --------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pagamentos AS
WITH base AS (
  SELECT *, COUNT(*) OVER () AS _linhas_origem
  FROM lakehouse_rotaperfume.bronze.pagamentos
)
SELECT
  pagamento_id,
  pedido_id,
  forma_pagamento,
  TRY_CAST(parcelas AS INT) AS parcelas,
  TRY_CAST(valor AS DECIMAL(18,2)) AS valor,
  TRY_CAST(taxa_pct AS DECIMAL(9,4)) AS taxa_pct,
  TRY_CAST(valor_liquido AS DECIMAL(18,2)) AS valor_liquido,
  coalesce(try_to_date(data_vencimento), try_to_date(data_vencimento, 'dd/MM/yyyy')) AS data_vencimento,
  coalesce(try_to_date(data_pagamento), try_to_date(data_pagamento, 'dd/MM/yyyy')) AS data_pagamento,
  status_pagamento,
  current_timestamp() AS _processado_em,
  _linhas_origem
FROM base;

COMMENT ON TABLE lakehouse_rotaperfume.silver.pagamentos IS
  'Pagamentos tipados. data_pagamento NULL significa pagamento ainda em aberto.';

ALTER TABLE lakehouse_rotaperfume.silver.pagamentos ALTER COLUMN data_pagamento COMMENT
  'NULL quando o pagamento ainda não ocorreu (status_pagamento = Em aberto/Inadimplente) — preservado, não inventado.';

-- estoque -----------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.estoque AS
WITH base AS (
  SELECT *, COUNT(*) OVER () AS _linhas_origem
  FROM lakehouse_rotaperfume.bronze.estoque
)
SELECT
  coalesce(try_to_date(data_snapshot), try_to_date(data_snapshot, 'dd/MM/yyyy')) AS data_snapshot,
  sku,
  TRY_CAST(saldo AS INT) AS saldo,
  TRY_CAST(saldo AS INT) = 0 AS ruptura,
  current_timestamp() AS _processado_em,
  _linhas_origem
FROM base;

COMMENT ON TABLE lakehouse_rotaperfume.silver.estoque IS
  'Estoque tipado. ruptura é derivada de saldo = 0 — a flag ruptura da bronze é ignorada de propósito, por não ser confiável como fonte.';

ALTER TABLE lakehouse_rotaperfume.silver.estoque ALTER COLUMN ruptura COMMENT
  'Derivada de saldo = 0, não da coluna ruptura da bronze.';
