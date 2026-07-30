# AGENTS.md

Read natively by Codex and ~30 other agents; Claude Code reads it via the import
in `CLAUDE.md`. Codex concatenates nested AGENTS.md files root-down and caps the
total at `project_doc_max_bytes` (32 KiB), so keep this file well under that.

Rules here are imperative and checkable on purpose. "Be rigorous" is not a rule;
"change exactly one variable per experiment" is.

## Setup

- Python is a pixi environment (conda-forge) at `.pixi/envs/default`, already on
  `PATH`. Bare `python` and `pytest` work.
- Use `pixi run <task>` for real work: it applies the environment's activation
  scripts, which conda-forge CUDA builds depend on.
- GPU environment: `pixi run -e gpu <cmd>`.
- Outbound network is default-deny. A failed download is the firewall, not a
  flaky mirror — say so rather than retrying or looking for a workaround.
- `.devcontainer/` is mounted read-only. Do not try to change it.

## Commands

| Task | Command |
|---|---|
| Tests | `pixi run test` |
| Lint | `pixi run lint` |
| Format | `pixi run fmt` |
| Types | `pixi run types` |
| All checks | `pixi run check` |
| Add a dependency | `pixi add <pkg>` (never bare `pip install`) |
| Profile a running process | `py-spy dump --pid <pid>` |

## Dependencies

- `pixi.toml` is the only way to add a package. `pixi add <pkg>` for conda-forge,
  `pixi add --pypi <pkg>` only when it genuinely isn't on conda-forge.
- Commit `pixi.toml` and `pixi.lock` in the same change. A lockfile that
  disagrees with the manifest is a bug.
- Pin the minor for `python` and `pytorch`; leave others loose. `pixi.lock` does
  the exact pinning.

## Code style

- Annotate tensor shapes with `jaxtyping`: `Float[Tensor, "batch seq dim"]`.
  `beartype` checks them at runtime. A wrong-shape bug that broadcasts silently
  costs a day; an annotation costs a line.
- Seeds and hyperparameters are Hydra config values, never literals in source.
- Notebooks: pair with `jupytext`, and never commit outputs (`nbstripout` runs
  on commit). Move anything reusable out of a notebook and into `src/`.

## Experiments

These are adapted from the "ten commandments" in *The Agentic Researcher*
(Zimmer et al., ZIB Berlin, arXiv:2603.15914), which derived each rule from an
observed agent failure mode rather than from theory.

- **One variable per experiment.** If two things change and the metric improves,
  you have learned nothing about which one helped.
- **Evaluate in tiers.** Tier 1 (seconds): does it run? Tier 2 (minutes): any
  signal on a small subset? Tier 3: the real metric that goes in the report. Use
  small runs to catch bugs only — never draw conclusions from them.
- **A crash is a bug, not a verdict.** Do not discard a method because the
  implementation failed. An OOM means reduce memory (`torch.cuda.empty_cache()`
  between runs, gradient checkpointing, sequential layers, and read
  `torch.cuda.memory_summary()` to find the spiking allocation), not "it doesn't
  scale". Report a scaling limit only after those fail.
- **Bound your expectations.** Before implementing a heuristic, work out the
  theoretical best case. A 2% gain means nothing until you know whether the
  ceiling is 3% or 300%.
- **Never manipulate evaluation.** Do not touch metrics, test sets, fixed
  hyperparameters, or problem definitions to make a result look better. Do not
  cherry-pick seeds. Changing the eval sample count "to speed things up" is this
  failure, even when unintentional.
- **Verify before claiming.** Assume you are wrong until a script says otherwise.
  Write verification scripts, not explanations. Try actively to falsify your own
  result. Label every claim verified, partially verified, or unverified.
- **Record everything.** Each experiment gets an entry in `report.md`: goal,
  hypothesis, method, results table, analysis, next steps. Include failures.
  If it is not in the report, it did not happen. Plot distributions and
  comparisons rather than describing them. Keep `TODO.md` current for open
  questions, unverified claims, and deferred work.
- **Do not start a full training run on your own initiative.** GPU-hours are a
  cost nobody agreed to. Validate on one batch first, and say what you ran.
- Long jobs go in `tmux`, with output redirected to a log file that you check
  with `tail`. Do not stream a training log into your own context.
- Before claiming an improvement, state whether it exceeds run-to-run variance.

## Filesystem

- `data/` and `/data` are read-only inputs. Never write there.
- All run artefacts go to `outputs/`. Never commit datasets, checkpoints,
  `wandb/`, or notebook outputs.
- Large downloads go to the cache volume via `HF_HOME` / `TORCH_HOME`, already
  configured. Never download models into the workspace.

## Git

- Commit each experiment as `exp(EXXX): <description> -- <metric>=<value>`, so
  `git log` doubles as the experiment index.
- Never rewrite published history. Never `push --force`.

## Done means

`pixi run check` passes, the experiment is in `report.md`, and any bug you fixed
has a test.
