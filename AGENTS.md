# Agent instructions

Read by Codex directly and by Claude Code via the import in `CLAUDE.md`.

## Environment

- Python is a pixi environment (conda-forge) at `.pixi/envs/default`, already on
  `PATH`. Bare `python` and `pytest` work; prefer `pixi run <task>` for anything
  real, since it also applies activation scripts that CUDA builds depend on.
- `pixi.toml` is the only way to add a dependency: `pixi add <pkg>`, or
  `pixi add --pypi <pkg>` if it isn't on conda-forge. Never bare `pip install`.
  Commit `pixi.toml` and `pixi.lock` together.
- Outbound network is default-deny. A failed download is the firewall, not a
  flaky mirror — say so instead of retrying or looking for a workaround.
- `.devcontainer/` is mounted read-only. Don't try to change it.

## Experiments

- Don't launch full training runs on your own initiative; they cost GPU-hours
  nobody agreed to. Validate with a single batch or a tiny subset first, and say
  what you ran.
- Long jobs go in `tmux`, not your foreground shell.
- `data/` and `/data` are read-only. Write artefacts to `outputs/`. Never commit
  datasets, checkpoints, or notebook outputs.
- Seed everything, and make the seed a parameter.
- Before claiming an improvement, say whether the change exceeds run-to-run
  variance. Don't quietly alter hyperparameters or metric definitions while
  fixing something else.

## Done means

`pixi run check` passes, and any bug you fixed has a test.