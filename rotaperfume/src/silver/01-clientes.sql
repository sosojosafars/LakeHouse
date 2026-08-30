-- Silver: clientes limpos e deduplicados por CNPJ.
-- 40 CNPJs têm 2 cadastros na origem (grafias diferentes de pontuação/espaço);
-- mantemos o cadastro mais antigo e guardamos os ids descartados em
-- cliente_ids_duplicados, porque pedidos antigos ainda apontam para eles.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.clientes AS
WITH base AS (
  SELECT *, COUNT(*) OVER () AS _linhas_origem
  FROM lakehouse_rotaperfume.bronze.clientes
),
normalizado AS (
  SELECT
    cliente_id,
    lpad(regexp_replace(trim(cnpj), '[^0-9]', ''), 14, '0') AS cnpj,
    regexp_replace(initcap(trim(razao_social)), '\\s+', ' ') AS razao_social,
    segmento,
    cidade,
    uf,
    bairro,
    coalesce(try_to_date(data_cadastro), try_to_date(data_cadastro, 'dd/MM/yyyy')) AS data_cadastro,
    ativo = 'S' AS ativo,
    _linhas_origem
  FROM base
),
ranked AS (
  SELECT
    *,
    row_number() OVER (PARTITION BY cnpj ORDER BY data_cadastro ASC, cliente_id ASC) AS ordem,
    array_except(collect_list(cliente_id) OVER (PARTITION BY cnpj), array(cliente_id)) AS ids_descartados
  FROM normalizado
)
SELECT
  cliente_id,
  cnpj,
  razao_social,
  segmento,
  cidade,
  uf,
  bairro,
  data_cadastro,
  ativo,
  CASE WHEN size(ids_descartados) > 0 THEN ids_descartados END AS cliente_ids_duplicados,
  current_timestamp() AS _processado_em,
  _linhas_origem
FROM ranked
WHERE ordem = 1;

ALTER TABLE lakehouse_rotaperfume.silver.clientes ADD CONSTRAINT cnpj_14_digitos CHECK (length(cnpj) = 14);
ALTER TABLE lakehouse_rotaperfume.silver.clientes ADD CONSTRAINT data_cadastro_nao_nula CHECK (data_cadastro IS NOT NULL);

COMMENT ON TABLE lakehouse_rotaperfume.silver.clientes IS
  'Clientes limpos e deduplicados por CNPJ: mantém o cadastro mais antigo quando há duplicidade.';

ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN cnpj COMMENT
  'Normalizado para 14 dígitos numéricos (trim + regexp_replace + lpad). Nunca convertido para número, para não perder zero à esquerda.';
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN razao_social COMMENT
  'Padronizada com initcap e espaço duplo colapsado.';
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN data_cadastro COMMENT
  'Convertida com try_to_date cobrindo os dois formatos de origem (ISO e dd/MM/yyyy) — to_date abortaria em ANSI mode com data malformada.';
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN cliente_ids_duplicados COMMENT
  'IDs de cadastros duplicados do mesmo CNPJ, descartados na deduplicação (mantido o cadastro mais antigo). Pedidos antigos podem apontar para esses ids.';
