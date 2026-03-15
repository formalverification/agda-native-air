# experiments/archive/

This directory preserves code from a prior private development phase that is
not part of the current architecture.  It is kept for
research continuity and may be revived in later phases.

**Nothing here is maintained or tested in CI.**

## Contents

### ml-pipeline/

Superseded components from the ML pipeline:

- `python/api/` — FastAPI server, retired in PLAN v2 (replaced by `agda-mcp`)
- `python/model/train.py` — legacy MLP trainer (superseded by retrieval-first approach)
- `python/model/batch_infer.py` — batch inference for legacy MLP
- `python/model/export_onnx.py` — ONNX export (Phase 3+ at earliest)
- `python/model/export_script.py` — TorchScript export
- `python/model/build_finetune_dataset.py` — instruction-tuning dataset builder (premature)
- `python/tests/test_main.py` — tests for the FastAPI app
- `python/tests/test_dataset_pipeline.py` — tests for `build_finetune_dataset.py`
- `scripts/start_server.sh` — FastAPI server launcher
- `scripts/train_model.sh` — legacy MLP trainer wrapper
- `scripts/venv-gpu.sh` — Jetson GPU venv setup (premature until Phase 3)
- `Makefile` — deprecated sub-Makefile (all its targets drive archived code)
- `Dockerfile` — Docker image for FastAPI serving

### strux-driver/

- `Agda2TrainReducer.scala` — legacy A2T reducer; relevant only for a potential
  future collaboration with Orestis Melkonian (AGDA2TRAIN / QUILL)

See `docs/PLAN.md` for the current architecture.
