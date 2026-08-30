#!/usr/bin/env bash
# Creates the rotaperfume catalog, if it doesn't exist yet.
#
# This lives outside the bundle on purpose:
# - Databricks Asset Bundles have no `catalogs` resource type (only `schemas`,
#   `volumes`, etc. inside a catalog that already exists) — the catalog itself
#   has to exist before `databricks bundle deploy` can create the schemas in
#   resources/catalogo.yml.
# - In workspaces with Default Storage enabled (common on Free Edition),
#   creating a catalog through the API/Terraform provider fails with
#   "Metastore storage root URL does not exist. Default Storage is enabled
#   in your account." (400 INVALID_STATE). The SQL path below works there.
#
# Usage: scripts/criar-catalogo.sh <profile>
set -euo pipefail

PROFILE="${1:?usage: criar-catalogo.sh <profile>}"
CATALOG="lakehouse_rotaperfume"
WAREHOUSE_ID="10eb01bbaddccb09" # Serverless Starter Warehouse

databricks experimental aitools tools query \
  --profile "$PROFILE" \
  --warehouse "$WAREHOUSE_ID" \
  "CREATE CATALOG IF NOT EXISTS ${CATALOG}"
