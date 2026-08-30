# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo layout

This repo has two independent parts:

- `rotaperfume/` — a Databricks Asset Bundle (DAB) project. All bundle config, source code, and tests live here. Treat this as the actual project root for build/test/deploy purposes.
- `dados/` — raw CSV sample data for a fictional B2B perfume distributor ("rotaperfume"), used as source data for the bundle's pipeline. ERP-style tables: `produtos`, `pedidos`, `itens_pedido`, `pagamentos`, `estoque`. CRM-style tables: `clientes`, `vendedores`, `carteira`, `oportunidades`, `visitas`.

**Before any other action in this repo, read `rotaperfume/AGENTS.md`** — it requires reading the `databricks-core` skill first for CLI auth, profile selection, data discovery, and the bundle deployment workflow. `rotaperfume/CLAUDE.md` imports `AGENTS.md` directly.

`.llm/prompts.01.md` is course/lesson-plan material (in Portuguese) describing how this bundle is meant to be built out step by step across several sessions (medallion layers, catalog-as-code, arrival checks, etc.). It documents an *intended* target state — profile names, hosts, and folder layout (`dados/erp`, `dados/crm`) it references don't necessarily match the bundle's current `databricks.yml` or the current flat `dados/` layout. Use it for domain/direction context, not as a source of current config truth — verify against the actual files before relying on it.

## Commands

All commands run from `rotaperfume/`.

- Install deps: `uv sync --dev`
- Run all tests: `uv run pytest`
- Run a single test: `uv run pytest tests/sample_taxis_test.py::test_find_all_taxis`
- Lint: `uv run ruff check .` (line length 120, configured in `pyproject.toml`)
- Validate bundle: `databricks bundle validate --target dev`
- Deploy bundle (dev): `databricks bundle deploy` (dev is the default target)
- Deploy bundle (prod): `databricks bundle deploy --target prod`
- Run a job/pipeline: `databricks bundle run`
- Run a single DLT transformation: `databricks bundle run LakeHousePerfume_etl --refresh <transformation_name>`

Tests require Databricks Connect and talk to a real Databricks workspace (serverless compute is used automatically if none is configured) — there is no local Spark mock.

## Architecture

This is a Databricks Asset Bundle generated from the `default-python` template (bundle name `LakeHousePerfume`, catalog `lakehouse_rotaperfume`). Bundle definition is `rotaperfume/databricks.yml`, which includes all YAML under `resources/`.

- `resources/LakeHousePerfume_etl.pipeline.yml` — declares the `LakeHousePerfume_etl` Lakeflow Declarative Pipeline (serverless), whose libraries are all files under `src/LakeHousePerfume_etl/transformations/**`.
- `resources/sample_job.job.yml` — a daily job chaining a notebook task, a python wheel task (entry point `LakeHousePerfume.main:main`), and a pipeline refresh task.
- `src/LakeHousePerfume/` — the shared Python package (built as a wheel via `uv build --wheel`, declared as the `python_artifact` bundle artifact). `main.py` is the wheel-task entry point; it takes `--catalog`/`--schema` args and calls into modules like `taxis.py`.
- `src/LakeHousePerfume_etl/transformations/` — one file per dataset, using `@dp.table` decorators (`pyspark.pipelines` / DLT syntax). This is where new pipeline datasets get added, one file each.
- `src/LakeHousePerfume_etl/explorations/` — ad-hoc notebooks, excluded from git (see `.gitignore`'s `**/explorations/**`).
- `tests/conftest.py` — provides `spark` (a `DatabricksSession`) and `load_fixture` (loads JSON/CSV from `fixtures/`) pytest fixtures, and eagerly initializes/validates the Databricks Connect session at collection time.

`databricks.yml` currently defines only the default-template `dev`/`prod` targets (both pointed at the same workspace host); `dev` uses `mode: development` (resource-name prefixing). Everything under `resources/`, `src/LakeHousePerfume_etl/`, and the catalog/schema/volume layout described in `.llm/prompts.01.md` is still the template scaffold — expect it to be replaced as the project is built out following that lesson plan.
