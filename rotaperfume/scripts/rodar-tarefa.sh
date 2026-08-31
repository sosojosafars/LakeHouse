#!/usr/bin/env bash
# Runs a single task of the rotaperfume_pipeline job, instead of the whole
# job — each serverless task pays its own startup time, and the full job
# pays it thirteen-plus times over. Use this while iterating on one task;
# run the full job (databricks bundle run rotaperfume_pipeline) only once,
# at the end, to see the whole DAG green.
#
# Usage: scripts/rodar-tarefa.sh <profile> <task_key> [target]
set -euo pipefail

PROFILE="${1:?usage: rodar-tarefa.sh <profile> <task_key> [target]}"
TASK_KEY="${2:?usage: rodar-tarefa.sh <profile> <task_key> [target]}"
TARGET="${3:-dev}"

databricks bundle run rotaperfume_pipeline \
  --target "$TARGET" \
  --profile "$PROFILE" \
  --only "$TASK_KEY"
