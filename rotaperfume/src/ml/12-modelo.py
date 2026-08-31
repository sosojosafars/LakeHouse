# Databricks notebook source
# MAGIC %md
# MAGIC # O modelo e o MLflow
# MAGIC Baseline antes de treinar qualquer coisa: três regras simples usadas como
# MAGIC score, avaliadas no mesmo holdout do modelo. Só depois vem o
# MAGIC `HistGradientBoostingClassifier`, registrado no Unity Catalog (alias `@prod`)
# MAGIC e usado para pontuar `gold.features_cliente`.

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------

import mlflow
import mlflow.sklearn
import pandas as pd
from databricks.sdk import WorkspaceClient
from mlflow import MlflowClient
from mlflow.models import infer_signature
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.inspection import permutation_importance
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import StratifiedKFold, cross_val_predict, train_test_split

NOME_MODELO_UC = f"{catalog}.gold.propensao_compra"

FEATURE_COLS = [
    "recencia_dias", "frequencia_pedidos", "valor_total", "ticket_medio",
    "margem_total", "margem_percentual",
    "intervalo_medio_dias", "desvio_intervalo_dias", "atraso_relativo",
    "pedidos_ultimos_90d",
    "oportunidades_abertas", "oportunidades_ganhas", "taxa_ganho",
    "visitas_90d", "conversao_visita",
    "skus_distintos", "categorias_distintas", "marcas_distintas",
    "concentracao_marca_top", "comprou_lancamento",
]

BASELINE_LABELS = {
    "recencia": "ligue para quem comprou recentemente",
    "valor_total": "ligue para quem compra mais",
    "atraso_relativo": "ligue para quem esta atrasado",
}

FAIXAS = {1: "Fria", 2: "Morna", 3: "Quente", 4: "Muito quente"}

# COMMAND ----------

pdf_treino = (
    spark.table(f"{catalog}.gold.features_treino")
    .select("cliente_id", *FEATURE_COLS, "comprou_em_7d")
    .toPandas()
)

X = pdf_treino[FEATURE_COLS]
y = pdf_treino["comprou_em_7d"]
TAXA_BASE = float(y.mean())

X_train, X_holdout, y_train, y_holdout = train_test_split(
    X, y, test_size=0.25, stratify=y, random_state=42
)

# COMMAND ----------

# BASELINE — regra simples usada como score, sem modelo nenhum. atraso_relativo
# é NULL para cliente de um pedido só: cai fora do cálculo desse baseline
# específico (notna), sem afetar recencia_dias/valor_total, que nunca são NULL.
scores_baseline = {
    "recencia": -X_holdout["recencia_dias"],
    "valor_total": X_holdout["valor_total"],
    "atraso_relativo": X_holdout["atraso_relativo"],
}
auc_baseline = {}
for chave, score in scores_baseline.items():
    validos = score.notna()
    auc_baseline[chave] = roc_auc_score(y_holdout[validos], score[validos])

melhor_baseline_auc = max(auc_baseline.values())

print(f"{BASELINE_LABELS['recencia']:55s} {auc_baseline['recencia']:.4f}")
print(f"{'moeda (referencia)':55s} 0.5000")
print(f"{BASELINE_LABELS['valor_total']:55s} {auc_baseline['valor_total']:.4f}")
print(f"{BASELINE_LABELS['atraso_relativo']:55s} {auc_baseline['atraso_relativo']:.4f}")

# COMMAND ----------

# TREINO — HistGradientBoostingClassifier trata NaN nativamente: as features
# de ritmo são NULL de propósito para cliente de um pedido só, não imputar.
modelo_holdout = HistGradientBoostingClassifier(random_state=42)
modelo_holdout.fit(X_train, y_train)

auc_holdout = roc_auc_score(y_holdout, modelo_holdout.predict_proba(X_holdout)[:, 1])
print(f"{'modelo':55s} {auc_holdout:.4f}")

# COMMAND ----------

# IMPORTANCIA POR PERMUTACAO, no holdout
resultado_importancia = permutation_importance(
    modelo_holdout, X_holdout, y_holdout, n_repeats=5, random_state=42, scoring="roc_auc"
)
importancias = pd.Series(
    resultado_importancia.importances_mean, index=FEATURE_COLS
).sort_values(ascending=False)
print(importancias.head(10))
feature_top1 = importancias.index[0]

# COMMAND ----------

# LIFT — out-of-fold sobre TODO features_treino, não só o holdout: a fila real
# é 200 de ~2.800, e um holdout de ~700 superestimaria o lift (200 seria 28%
# da amostra).
oof_scores = cross_val_predict(
    HistGradientBoostingClassifier(random_state=42),
    X, y,
    cv=StratifiedKFold(n_splits=5, shuffle=True, random_state=42),
    method="predict_proba",
)[:, 1]

top200 = (
    pdf_treino.assign(_score_oof=oof_scores)
    .sort_values("_score_oof", ascending=False)
    .head(200)
)
acertos_top200 = int(top200["comprou_em_7d"].sum())
lift_top200 = (acertos_top200 / 200) / TAXA_BASE
print(f"acertos_top200={acertos_top200} lift_top200={lift_top200:.4f}")

# COMMAND ----------

# modelo_final é reajustado em 100% de features_treino: o holdout serve só
# para avaliação honesta, o artefato de produção usa todo o dado rotulado.
modelo_final = HistGradientBoostingClassifier(random_state=42)
modelo_final.fit(X, y)

# COMMAND ----------

usuario_atual = WorkspaceClient().current_user.me().user_name
pasta_experimentos = f"/Users/{usuario_atual}/rotaperfume-experimentos"
WorkspaceClient().workspace.mkdirs(pasta_experimentos)

mlflow.set_registry_uri("databricks-uc")
mlflow.set_experiment(f"{pasta_experimentos}/propensao_compra")

with mlflow.start_run() as run:
    mlflow.log_params(modelo_final.get_params())
    mlflow.log_metric("auc", auc_holdout)
    mlflow.log_metric("lift_top200", lift_top200)
    mlflow.log_metric("acertos_top200", acertos_top200)
    mlflow.log_metric("taxa_base", TAXA_BASE)
    # o Unity Catalog exige signature (schema de entrada/saida) para registrar
    assinatura = infer_signature(X, modelo_final.predict(X))
    # artifact_path=, nao name=: o serverless roda MLflow 2.22, o name= e sintaxe do MLflow 3
    mlflow.sklearn.log_model(
        modelo_final, artifact_path="modelo", signature=assinatura, input_example=X.head(5)
    )
    run_id = run.info.run_id

versao_registrada = mlflow.register_model(f"runs:/{run_id}/modelo", NOME_MODELO_UC)
MlflowClient().set_registered_model_alias(NOME_MODELO_UC, "prod", versao_registrada.version)
VERSAO = int(versao_registrada.version)

# COMMAND ----------

# TRES TESTES QUE INTERROMPEM A TAREFA — nesta ordem, depois do registro no UC:
# se o job quebrar aqui, a versao ja registrada/aliada e a suspeita, nao a
# tarefa em si (a tarefa falhando e a defesa contra vazamento e regressao).
assert auc_holdout - melhor_baseline_auc >= 0.05, (
    f"Modelo (auc={auc_holdout:.4f}) nao bateu o melhor baseline "
    f"(auc={melhor_baseline_auc:.4f}) por pelo menos 0.05"
)
assert auc_holdout < 0.99, f"AUC {auc_holdout:.4f} bom demais — suspeita de vazamento de dado"
assert lift_top200 >= 2.5, f"lift_top200={lift_top200:.4f} abaixo de 2.5 — fila nao compensa o projeto"

# COMMAND ----------

pdf_cliente = (
    spark.table(f"{catalog}.gold.features_cliente")
    .select("cliente_id", *FEATURE_COLS)
    .toPandas()
)
# seleciona/ordena pelas colunas do treino, nao pela ordem da tabela
X_score = pdf_cliente[list(modelo_final.feature_names_in_)]
pdf_cliente["score"] = modelo_final.predict_proba(X_score)[:, 1]

df_scores = spark.createDataFrame(pdf_cliente[["cliente_id", "score"]])

janela_score = Window.orderBy("score")
df_score_propensao = (
    spark.table(f"{catalog}.gold.features_cliente")
    .select("cliente_id", "_referencia")
    .join(df_scores, "cliente_id")
    .withColumn("_ntile", F.ntile(4).over(janela_score))
    .withColumn(
        "faixa",
        F.when(F.col("_ntile") == 1, FAIXAS[1])
        .when(F.col("_ntile") == 2, FAIXAS[2])
        .when(F.col("_ntile") == 3, FAIXAS[3])
        .otherwise(FAIXAS[4]),
    )
    .withColumn("cliente_id", F.col("cliente_id").cast("int"))
    .withColumn("versao", F.lit(VERSAO))
    .select("cliente_id", "score", "faixa", "_referencia", "versao")
)

(
    df_score_propensao.write.format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(f"{catalog}.gold.score_propensao")
)
spark.sql(
    f"COMMENT ON TABLE {catalog}.gold.score_propensao IS "
    "'Um score de propensao de compra em 7 dias por cliente (0 a 1), com faixa "
    "(NTILE(4): Fria/Morna/Quente/Muito quente) e a versao do modelo no Unity "
    "Catalog que gerou o score. Gerada por src/ml/12-modelo.py.'"
)

# COMMAND ----------

pdf_holdout_resultado = X_holdout.copy()
pdf_holdout_resultado["comprou_em_7d"] = y_holdout.values
pdf_holdout_resultado["score"] = modelo_holdout.predict_proba(X_holdout)[:, 1]

df_calibragem_holdout = (
    spark.createDataFrame(pdf_holdout_resultado[["score", "comprou_em_7d"]])
    .withColumn("_ntile", F.ntile(4).over(Window.orderBy("score")))
    .withColumn(
        "faixa",
        F.when(F.col("_ntile") == 1, FAIXAS[1])
        .when(F.col("_ntile") == 2, FAIXAS[2])
        .when(F.col("_ntile") == 3, FAIXAS[3])
        .otherwise(FAIXAS[4]),
    )
    .groupBy("faixa")
    .agg(
        F.count("*").alias("clientes"),
        F.sum("comprou_em_7d").alias("compraram"),
        F.avg(F.col("comprou_em_7d").cast("double")).alias("taxa_de_compra"),
        F.avg("score").alias("score_medio"),
    )
)

(
    df_calibragem_holdout.write.format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(f"{catalog}.gold.calibragem_holdout")
)
spark.sql(
    f"COMMENT ON TABLE {catalog}.gold.calibragem_holdout IS "
    "'Calibragem do score por faixa (NTILE(4)), calculada no holdout do treino: "
    "clientes, quantos compraram, taxa de compra e score medio. A taxa de compra "
    "deve subir da faixa fria para a muito quente — prova de que o score ordena, "
    "sem precisar explicar AUC. Gerada por src/ml/12-modelo.py.'"
)

# COMMAND ----------

linha_metricas = pd.DataFrame([{
    "versao": VERSAO,
    "auc": auc_holdout,
    "lift_top200": lift_top200,
    "acertos_top200": acertos_top200,
    "taxa_base": TAXA_BASE,
    "auc_baseline_recencia": auc_baseline["recencia"],
    "auc_baseline_valor_total": auc_baseline["valor_total"],
    "auc_baseline_atraso_relativo": auc_baseline["atraso_relativo"],
    "feature_top1": feature_top1,
}])

df_modelo_metricas = spark.createDataFrame(linha_metricas).withColumn(
    "_treinado_em", F.current_timestamp()
)

(
    df_modelo_metricas.write.format("delta")
    .mode("append")
    .saveAsTable(f"{catalog}.gold.modelo_metricas")
)
spark.sql(
    f"COMMENT ON TABLE {catalog}.gold.modelo_metricas IS "
    "'Uma linha por treino do modelo de propensao: versao no UC, auc e "
    "lift_top200/acertos_top200 do holdout/out-of-fold, taxa base, AUC dos tres "
    "baselines simples e a feature nº 1 por importancia de permutacao. "
    "Gerada por src/ml/12-modelo.py.'"
)
