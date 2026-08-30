# Databricks notebook source
# MAGIC %md
# MAGIC # Conferência de chegada — raw
# MAGIC Confere que os 10 arquivos ERP/CRM chegaram ao Volume `bronze.raw` antes de
# MAGIC qualquer transformação rodar. Arquivo que não chega não dá erro — dá número
# MAGIC menor, e o dashboard mostra receita pela metade com cara de número certo.

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------

from datetime import datetime, timezone

ARQUIVOS_ESPERADOS = {
    "erp": ["produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"],
    "crm": ["clientes", "vendedores", "carteira", "oportunidades", "visitas"],
}

VOLUME_RAIZ = f"/Volumes/{catalog}/bronze/raw"

# COMMAND ----------

resultados = []
erros = []

for sistema, arquivos in ARQUIVOS_ESPERADOS.items():
    for arquivo in arquivos:
        caminho = f"{VOLUME_RAIZ}/{sistema}/{arquivo}.csv"
        try:
            info = dbutils.fs.ls(caminho)[0]
        except Exception:
            erros.append(f"{sistema}/{arquivo}.csv não encontrado em {caminho}")
            continue

        linhas = spark.read.option("header", True).csv(caminho).count()
        if linhas == 0:
            erros.append(f"{sistema}/{arquivo}.csv chegou vazio (0 linhas de dado)")

        resultados.append(
            {
                "sistema": sistema,
                "arquivo": f"{arquivo}.csv",
                "bytes": info.size,
                "linhas": linhas,
                "conferido_em": datetime.now(timezone.utc),
            }
        )

if erros:
    raise Exception("Conferência de chegada falhou:\n" + "\n".join(erros))

# COMMAND ----------

resultado_df = spark.createDataFrame(resultados)

spark.sql(f"USE CATALOG `{catalog}`")
(
    resultado_df.write.mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable("bronze._raw_arquivos")
)
spark.sql(
    "COMMENT ON TABLE bronze._raw_arquivos IS "
    "'Controle de conferência de chegada dos arquivos raw (ERP/CRM): tamanho e "
    "número de linhas confirmados a cada execução do pipeline.'"
)

# COMMAND ----------

print(f"{'sistema':<8} {'arquivo':<20} {'bytes':>10} {'linhas':>10}  conferido_em")
for r in sorted(resultados, key=lambda r: -r["linhas"]):
    print(f"{r['sistema']:<8} {r['arquivo']:<20} {r['bytes']:>10} {r['linhas']:>10}  {r['conferido_em']}")
