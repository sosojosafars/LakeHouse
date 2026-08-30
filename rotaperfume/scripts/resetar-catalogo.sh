#!/usr/bin/env bash
# ATENÇÃO: destrutivo e irreversível.
#
# Apaga o catalog lakehouse_rotaperfume inteiro (schemas bronze/silver/gold e
# tudo que tiver dentro, incluindo o volume bronze.raw e qualquer tabela).
# Existe para zerar o estado manual/ad-hoc do workspace antes do primeiro
# `databricks bundle deploy` — não é chamado por nenhum outro script ou job.
#
# Usage: scripts/resetar-catalogo.sh <profile>
set -euo pipefail

PROFILE="${1:?usage: resetar-catalogo.sh <profile>}"
CATALOG="lakehouse_rotaperfume"
WAREHOUSE_ID="10eb01bbaddccb09" # Serverless Starter Warehouse

databricks experimental aitools tools query \
  --profile "$PROFILE" \
  --warehouse "$WAREHOUSE_ID" \
  "DROP CATALOG IF EXISTS ${CATALOG} CASCADE"
