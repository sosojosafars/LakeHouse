# Databricks notebook source
# MAGIC %md
# MAGIC # Features de cliente — RFM, ritmo, CRM e mix
# MAGIC Uma função, `montar_features(referencia)`, devolve uma linha por cliente com
# MAGIC tudo que se sabia dele ATÉ `referencia` — cada fonte é filtrada pela sua
# MAGIC própria data na primeira linha da leitura. Chamada duas vezes: com rótulo
# MAGIC (`gold.features_treino`) e sem rótulo (`gold.features_cliente`), para que as
# MAGIC duas nunca possam divergir (training/serving skew).
# MAGIC
# MAGIC NÃO lê `gold.dim_cliente`: suas colunas agregam a base inteira, sem corte —
# MAGIC usar qualquer uma aqui seria vazamento.

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------

from datetime import date, timedelta

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window

JANELA_RECENTE_DIAS = 90
JANELA_LANCAMENTO_DIAS = 120
TETO_ATRASO_RELATIVO = 10.0

FEATURE_COLS = [
    # RFM
    "recencia_dias", "frequencia_pedidos", "valor_total", "ticket_medio",
    "margem_total", "margem_percentual",
    # Ritmo
    "intervalo_medio_dias", "desvio_intervalo_dias", "atraso_relativo",
    "pedidos_ultimos_90d",
    # CRM
    "oportunidades_abertas", "oportunidades_ganhas", "taxa_ganho",
    "visitas_90d", "conversao_visita",
    # Mix
    "skus_distintos", "categorias_distintas", "marcas_distintas",
    "concentracao_marca_top", "comprou_lancamento",
]

# colunas que devem virar 0 (nunca NULL) quando o cliente não tem nenhuma
# oportunidade/visita/lançamento — só o grupo Ritmo pode ficar NULL, para
# cliente com um pedido só
COLUNAS_ZERO_NAO_NULL = [
    "pedidos_ultimos_90d",
    "oportunidades_abertas", "oportunidades_ganhas", "taxa_ganho",
    "visitas_90d", "conversao_visita",
    "comprou_lancamento",
]

# COMMAND ----------


def montar_features(referencia: date) -> DataFrame:
    fato = (
        spark.table(f"{catalog}.gold.fato_vendas")
        .filter(F.col("data_pedido") < F.lit(referencia))
    )
    oportunidades = (
        spark.table(f"{catalog}.silver.oportunidades")
        .filter(F.col("data_abertura") < F.lit(referencia))
    )
    visitas = (
        spark.table(f"{catalog}.silver.visitas")
        .filter(F.col("data_visita") < F.lit(referencia))
        # 'gerou_pedido' não existe em silver.visitas — o resultado de negócio
        # equivalente é resultado = 'Pedido realizado' (confirmado com
        # SELECT DISTINCT resultado)
        .withColumn("gerou_pedido", F.col("resultado") == F.lit("Pedido realizado"))
    )

    universo = fato.select("cliente_id").distinct()

    inicio_recente = referencia - timedelta(days=JANELA_RECENTE_DIAS)
    inicio_lancamento = referencia - timedelta(days=JANELA_LANCAMENTO_DIAS)

    # RFM ---------------------------------------------------------------
    rfm = (
        fato.groupBy("cliente_id")
        .agg(
            F.datediff(F.lit(referencia), F.max("data_pedido")).alias("recencia_dias"),
            F.countDistinct("pedido_id").alias("frequencia_pedidos"),
            F.sum("receita").alias("valor_total"),
            F.sum("margem").alias("margem_total"),
        )
        .withColumn("ticket_medio", F.col("valor_total") / F.col("frequencia_pedidos"))
        .withColumn(
            "margem_percentual",
            F.col("margem_total") / F.nullif(F.col("valor_total"), F.lit(0)),
        )
    )

    # Ritmo ---------------------------------------------------------------
    datas_pedido = fato.select("cliente_id", "data_pedido").distinct()
    janela_cliente = Window.partitionBy("cliente_id").orderBy("data_pedido")
    gaps = (
        datas_pedido
        .withColumn("data_anterior", F.lag("data_pedido").over(janela_cliente))
        .withColumn("gap_dias", F.datediff("data_pedido", "data_anterior"))
        .filter(F.col("gap_dias").isNotNull())
    )
    ritmo = gaps.groupBy("cliente_id").agg(
        F.avg("gap_dias").alias("intervalo_medio_dias"),
        F.stddev("gap_dias").alias("desvio_intervalo_dias"),
    )

    pedidos_90d = (
        fato.filter(F.col("data_pedido") >= F.lit(inicio_recente))
        .groupBy("cliente_id")
        .agg(F.countDistinct("pedido_id").alias("pedidos_ultimos_90d"))
    )

    # CRM ---------------------------------------------------------------
    crm_oportunidades = (
        oportunidades.groupBy("cliente_id")
        .agg(
            # "aberta" = nem ganha nem perdida; a silver não tem coluna
            # 'perdida', só 'fechada' (= ganha OU perdido) e 'ganha'
            F.sum(F.when(~F.col("fechada"), 1).otherwise(0)).alias("oportunidades_abertas"),
            F.sum(F.when(F.col("ganha"), 1).otherwise(0)).alias("oportunidades_ganhas"),
            F.count("oportunidade_id").alias("total_oportunidades"),
        )
        .withColumn(
            "taxa_ganho",
            F.col("oportunidades_ganhas") / F.nullif(F.col("total_oportunidades"), F.lit(0)),
        )
        .drop("total_oportunidades")
    )

    crm_visitas_90d = (
        visitas.filter(F.col("data_visita") >= F.lit(inicio_recente))
        .groupBy("cliente_id")
        .agg(F.count("visita_id").alias("visitas_90d"))
    )
    crm_conversao = (
        visitas.groupBy("cliente_id")
        .agg(
            F.count("visita_id").alias("total_visitas"),
            F.sum(F.when(F.col("gerou_pedido"), 1).otherwise(0)).alias("visitas_com_pedido"),
        )
        .withColumn(
            "conversao_visita",
            F.col("visitas_com_pedido") / F.nullif(F.col("total_visitas"), F.lit(0)),
        )
        .drop("total_visitas", "visitas_com_pedido")
    )

    # Mix ---------------------------------------------------------------
    mix = fato.groupBy("cliente_id").agg(
        F.countDistinct("sku").alias("skus_distintos"),
        F.countDistinct("categoria").alias("categorias_distintas"),
        F.countDistinct("marca").alias("marcas_distintas"),
    )

    marca_receita = fato.groupBy("cliente_id", "marca").agg(F.sum("receita").alias("receita_marca"))
    marca_top = marca_receita.groupBy("cliente_id").agg(
        F.max("receita_marca").alias("receita_marca_top")
    )

    produtos_lancamento = (
        spark.table(f"{catalog}.gold.dim_produto")
        .filter(
            (F.col("data_lancamento") >= F.lit(inicio_lancamento))
            & (F.col("data_lancamento") < F.lit(referencia))
        )
        .select("sku")
    )
    comprou_lancamento = (
        fato.join(F.broadcast(produtos_lancamento), "sku")
        .select("cliente_id")
        .distinct()
        .withColumn("comprou_lancamento", F.lit(1))
    )

    # Junta tudo, do universo de clientes com pedido antes do corte -----
    features = (
        universo
        .join(rfm, "cliente_id", "left")
        .join(ritmo, "cliente_id", "left")
        .join(pedidos_90d, "cliente_id", "left")
        .join(crm_oportunidades, "cliente_id", "left")
        .join(crm_visitas_90d, "cliente_id", "left")
        .join(crm_conversao, "cliente_id", "left")
        .join(mix, "cliente_id", "left")
        .join(marca_top, "cliente_id", "left")
        .join(comprou_lancamento, "cliente_id", "left")
        .withColumn(
            "concentracao_marca_top",
            F.col("receita_marca_top") / F.nullif(F.col("valor_total"), F.lit(0)),
        )
        .withColumn(
            "atraso_relativo",
            F.when(
                F.col("intervalo_medio_dias").isNotNull() & (F.col("intervalo_medio_dias") > 0),
                # F.least() ignora nulo e devolve o outro valor: sem o when()
                # acima, cliente de um pedido só (intervalo_medio_dias NULL)
                # recebe o teto e vai para o topo da fila
                F.least(F.col("recencia_dias") / F.col("intervalo_medio_dias"), F.lit(TETO_ATRASO_RELATIVO)),
            ),
        )
        .fillna(0, subset=COLUNAS_ZERO_NAO_NULL)
    )

    for coluna in FEATURE_COLS:
        features = features.withColumn(coluna, F.col(coluna).cast("double"))

    return features.select("cliente_id", *FEATURE_COLS).withColumn("_referencia", F.lit(referencia))

# COMMAND ----------

CORTE_TREINO = date(2026, 8, 1)
FIM_JANELA_LABEL = CORTE_TREINO + timedelta(days=6)  # 2026-08-07, inclusive

compradores_semana = (
    spark.table(f"{catalog}.gold.fato_vendas")
    .filter(F.col("data_pedido").between(F.lit(CORTE_TREINO), F.lit(FIM_JANELA_LABEL)))
    .select("cliente_id").distinct()
    .withColumn("comprou_em_7d", F.lit(1))
)

df_treino = (
    montar_features(CORTE_TREINO)
    .join(compradores_semana, "cliente_id", "left")
    .fillna(0, subset=["comprou_em_7d"])
)

(
    df_treino.write.format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(f"{catalog}.gold.features_treino")
)
spark.sql(
    f"COMMENT ON TABLE {catalog}.gold.features_treino IS "
    "'Uma linha por cliente com as 20 features (RFM, ritmo, CRM, mix) calculadas "
    "com corte em 2026-08-01, mais o rótulo comprou_em_7d (pedido entre "
    "2026-08-01 e 2026-08-07). Gerada por montar_features() em src/ml/11-features.py.'"
)

# COMMAND ----------

CORTE_SCORE = date(2026, 8, 31)

df_cliente = montar_features(CORTE_SCORE)

(
    df_cliente.write.format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(f"{catalog}.gold.features_cliente")
)
spark.sql(
    f"COMMENT ON TABLE {catalog}.gold.features_cliente IS "
    "'Uma linha por cliente com as 20 features (RFM, ritmo, CRM, mix) calculadas "
    "com corte em 2026-08-31, sem rótulo — é o que será pontuado pelo modelo. "
    "Gerada pela mesma montar_features() de gold.features_treino.'"
)
