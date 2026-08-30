#!/usr/bin/env bash
# Uploads the raw ERP/CRM CSVs to the bronze.raw Unity Catalog Volume.
#
# Requires the catalog and the bronze.raw volume to already exist
# (scripts/criar-catalogo.sh + `databricks bundle deploy`).
#
# `databricks fs cp` needs the `dbfs:` scheme on the destination even though
# it's a UC Volume, not DBFS.
#
# Usage: scripts/subir-raw.sh <profile>
set -euo pipefail

PROFILE="${1:?usage: subir-raw.sh <profile>}"
CATALOG="lakehouse_rotaperfume"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DADOS_DIR="$SCRIPT_DIR/../../dados"

databricks fs cp --recursive --overwrite --profile "$PROFILE" \
  "$DADOS_DIR/erp" "dbfs:/Volumes/${CATALOG}/bronze/raw/erp"

databricks fs cp --recursive --overwrite --profile "$PROFILE" \
  "$DADOS_DIR/crm" "dbfs:/Volumes/${CATALOG}/bronze/raw/crm"
