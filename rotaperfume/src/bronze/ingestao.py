# Databricks notebook source
# MAGIC %md
# MAGIC # Ingestão bronze
# MAGIC Lê os 10 CSVs do Volume raw como texto puro — sem inferSchema, sem limpeza —
# MAGIC e grava cada um como tabela Delta em `bronze`. A sujeira é preservada de
# MAGIC propósito: limpar é trabalho da silver, feito sabendo o que se faz.

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------

from pyspark.sql import functions as F

TABELAS = [
    ("erp", "produtos"),
    ("erp", "pedidos"),
    ("erp", "itens_pedido"),
    ("erp", "pagamentos"),
    ("erp", "estoque"),
    ("crm", "clientes"),
    ("crm", "vendedores"),
    ("crm", "carteira"),
    ("crm", "oportunidades"),
    ("crm", "visitas"),
]

VOLUME_RAIZ = f"/Volumes/{catalog}/bronze/raw"

# COMMAND ----------


def ingerir(sistema: str, tabela: str) -> int:
    caminho = f"{VOLUME_RAIZ}/{sistema}/{tabela}.csv"

    df = (
        spark.read.format("csv")
        .option("header", True)
        .option("inferSchema", False)  # tudo string, de propósito
        .option("multiLine", False)  # CSVs são CRLF de linha única, não ligar multiLine
        .load(caminho)
    )
    if "_rescued_data" in df.columns:
        df = df.drop("_rescued_data")

    df = df.withColumn("_ingerido_em", F.current_timestamp()).withColumn(
        "_arquivo_origem", F.lit(f"{tabela}.csv")
    )

    (
        df.write.format("delta")
        .mode("overwrite")
        .option("overwriteSchema", "true")
        .saveAsTable(f"{catalog}.bronze.{tabela}")
    )
    spark.sql(
        f"COMMENT ON TABLE {catalog}.bronze.{tabela} IS "
        f"'Ingestão raw do sistema {sistema}, sem limpeza — texto como veio da origem.'"
    )
    return df.count()


# COMMAND ----------

raw_arquivos = {
    row["arquivo"]: row["linhas"]
    for row in spark.table(f"{catalog}.bronze._raw_arquivos").collect()
}

resultados = []
erros = []

for sistema, tabela in TABELAS:
    linhas = ingerir(sistema, tabela)
    esperado = raw_arquivos.get(f"{tabela}.csv")
    bate = esperado is not None and linhas == esperado
    if not bate:
        erros.append(f"{tabela}: bronze tem {linhas} linhas, _raw_arquivos registrou {esperado}")
    resultados.append({"tabela": tabela, "linhas": linhas, "esperado": esperado, "bate": bate})

if erros:
    raise Exception("Ingestão bronze divergiu da conferência de chegada:\n" + "\n".join(erros))

# COMMAND ----------

print(f"{'tabela':<16} {'linhas':>10} {'esperado':>10}  bate")
for r in sorted(resultados, key=lambda r: -r["linhas"]):
    print(f"{r['tabela']:<16} {r['linhas']:>10} {r['esperado']:>10}  {r['bate']}")
