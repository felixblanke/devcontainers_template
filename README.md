# ML research dev container: Claude Code + Codex

conda-forge Python via [pixi](https://pixi.sh), both agent CLIs, an egress
firewall. Copy into a project, edit three things, open.

## Prerequisites

- Docker (**rootless** is assumed — see note below) and the Dev Containers
  extension, or `npm i -g @devcontainers/cli`.
- For GPU: NVIDIA Container Toolkit on the host. Verify *before* building, since
  `hostRequirements.gpu: "optional"` silently skips a missing GPU:
  `docker run --rm --gpus all ubuntu nvidia-smi`

## Adopt it

1. Copy these into your project root:

   ```
   .devcontainer/{devcontainer.json,Dockerfile}   pixi.toml
   AGENTS.md   CLAUDE.md   verify.sh   .gitignore
   ```

2. Edit exactly three things:
   - `pixi.toml` → `name`, and your dependencies
   - `devcontainer.json` → `"name"`, and trim `OPENAI_ALLOWED_DOMAINS` to the
     hosts you actually need
   - `.gitignore` → merge with yours if you have one

3. **Dev Containers: Reopen in Container** (or `devcontainer up --workspace-folder .`).
   First open solves and downloads the environment; later opens reuse the volume.

4. Verify, **inside the container** — it refuses to run on the host:

   ```bash
   devcontainer exec --workspace-folder . bash verify.sh
   ```

   Expect all PASS, GPU SKIP on a laptop. Fix the first failure and re-run.

5. Sign in once (credentials live in volumes shared across projects):

   ```bash
   claude                      # browser flow; paste the code if the callback stalls
   codex login --device-auth   # device-code flow, more reliable in a container
   ```

6. Commit `pixi.lock` the first time it appears.

## Daily use

| | |
|---|---|
| `pixi add scikit-image` | add a dependency (updates `pixi.toml` + `pixi.lock`) |
| `pixi add --pypi foo` | only when it isn't on conda-forge |
| `pixi run test` / `lint` / `check` | tasks from `pixi.toml` |
| `pixi shell` | activated interactive shell |
| `pixi run -e gpu test` | the GPU environment |
| `claude` / `codex` | agents; both read `AGENTS.md` |
| `bash /usr/local/bin/post-start.sh` | re-resolve DNS after a CDN rotation |

Bare `python` and `pytest` work everywhere, including the non-interactive shells
agents spawn. Prefer `pixi run` for real work — it applies activation scripts
that conda-forge CUDA builds need.

## Things that will bite you

Each of these cost a debugging session; they're all already handled, so don't
"simplify" them away.

- **Rootless Docker → `remoteUser: root`.** Container uid 0 maps to your host
  user; `node` maps to a subuid, so its writes to the workspace produce git's
  *dubious ownership* on the host. If you run **rootful** Docker instead, switch
  back to `node`, repoint `/root/*` paths to `/home/node/*`, and make sure your
  host uid is 1000.
- Rebuilding: `--remove-existing-container` recreates the container;
  `--build-no-cache` rebuilds the image. Named volumes survive both — use
  `docker volume rm agents-claude agents-codex agents-history ml-caches` to
  really reset state (costs a re-login). Feature/CLI caches live in
  `~/.devcontainer` and `~/.cache/devcontainercli`.

## What persists across a rebuild

Conversations and credentials for both agents (`agents-claude`, `agents-codex`),
shell history (`agents-history`), model/dataset caches (`ml-caches`), and the
environment (`<project>-pixi`). Claude Code still deletes transcripts older than
`cleanupPeriodDays` — `.claude/settings.json` raises it to 365. Both agents key
history to the absolute workspace path, so renaming the local folder orphans it.

## Security, honestly

The firewall is a guard rail, not a boundary: it permits DNS to any nameserver,
allows all of GitHub (so `git push` is an exfiltration channel), and the agent
has root and can switch it off. What actually protects you is that `~/.ssh`,
`~/.aws` and your dotfiles don't exist in the container, and that
`SSH_AUTH_SOCK`/`GH_TOKEN` are cleared — push from the host or use a repo-scoped
PAT. `.devcontainer/` is mounted read-only because an `initializeCommand` added
there executes on your *host* at the next rebuild.

Prefer auto mode over `--dangerously-skip-permissions`. For genuinely untrusted
third-party code, use a VM or Claude Code on the web — [Anthropic's own
recommendation](https://code.claude.com/docs/en/sandbox-environments#choose-an-approach).
