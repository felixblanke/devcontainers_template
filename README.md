# Dev container: Python/ML research with Claude Code + Codex

conda-forge packages via [pixi](https://pixi.sh), both agent CLIs, and OpenAI's
egress firewall. Seven files, no bespoke shell scripts — every moving part is an
upstream artefact pinned by version or commit.

## Setup

1. Copy this tree into a project. Edit `pixi.toml` (name, dependencies) and
   `OPENAI_ALLOWED_DOMAINS` in `devcontainer.json`.
2. **Dev Containers: Reopen in Container.** The first open runs `pixi install`;
   later opens reuse the `.pixi` volume.
3. Sign in: `claude`, and `codex login --device-auth` (the device-code flow is
   more reliable in a container). Credentials persist in volumes shared across
   projects, so this is once, not once per repo.

## Commands

| | |
|---|---|
| `pixi add scikit-image` | add a dependency (updates `pixi.toml` + `pixi.lock`) |
| `pixi run test` / `lint` / `check` | tasks, defined in `pixi.toml` |
| `pixi shell` | interactive activated shell |
| `pixi run -e gpu test` | the GPU environment |
| `pixi update` | bump everything, commit `pixi.lock` |
| `bash /usr/local/bin/post-start.sh` | re-resolve DNS after a CDN rotation |

## What survives a container reset

Everything both agents write lives in named volumes, so a rebuild keeps it:

| | Where | Volume |
|---|---|---|
| Claude conversations (`--resume`, `--continue`, rewind) | `~/.claude/projects/<path>/<session>.jsonl` | `agents-claude` |
| Claude prompt recall, auto memory, plugins, settings, credentials | `~/.claude/`, `~/.claude.json` | `agents-claude` |
| Codex conversations (`codex resume`) | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | `agents-codex` |
| Codex prompt history, memories, session index, auth, config | `~/.codex/` | `agents-codex` |
| Shell history | `/commandhistory/.bash_history` | `agents-history` |
| Model/dataset downloads | `~/.cache` (`HF_HOME`, `TORCH_HOME`) | `ml-caches` |
| Python environment | `.pixi/` | `<project>-pixi` |

Three things make this actually work, and each is easy to get wrong:

- **`CLAUDE_CONFIG_DIR` must be set.** `~/.claude.json` holds the OAuth session and
  per-project trust, and it sits *outside* `~/.claude`. Setting the variable moves
  every `~/.claude` path, including that file, under the volume.
- **The mount points must exist in the image, owned by `node`.** A named volume
  mounted over a path the image doesn't have is created `root:root`, and both
  agents then fail to write. The Dockerfile `install -d -o node` line exists for
  this; don't remove it. (The `.pixi` volume is the exception — it lands inside
  the bind-mounted workspace, so `postCreateCommand` chowns it at runtime.)
- **Transcripts expire on their own.** Claude Code deletes anything older than
  `cleanupPeriodDays` (default 30) at startup, regardless of volumes.
  `.claude/settings.json` raises it to 365.

Both tools key history to the absolute workspace path, so history follows the
*folder name*: `resume` finds nothing if you rename the local directory or clone
into a differently-named one. That's also why `workspaceFolder` is left at the
default `/workspaces/<name>` rather than pinned to something fixed — a fixed path
would merge every project's transcripts into one bucket.

### Verify it yourself

Before rebuilding:

```bash
claude  # have a short conversation, then exit
codex   # same
ls ~/.claude/projects/*/ ~/.codex/sessions/*/*/*/ | tail
```

Then **Dev Containers: Rebuild Container**, and check:

```bash
ls -ld ~/.claude ~/.codex        # must be owned by node, not root
claude --resume                  # your conversation should be listed
codex resume --last              # should reopen it
history | tail                   # shell history should be there
```

If `ls -ld` shows `root root`, the Dockerfile's `install -d` line is missing or
the volume predates it — `docker volume rm agents-claude agents-codex` and
rebuild. (You'll re-authenticate once.)

## Read this before trusting the sandbox

The firewall is a guard rail, not a boundary. Three holes, none of them fixable
without more machinery than this template is worth:

- **DNS to any nameserver is allowed**, so data can leave over DNS. Anthropic has
  [an open issue](https://github.com/anthropics/claude-code/issues/36907) for the
  same hole in their reference container.
- **All of GitHub is allowed** (`CODEX_INCLUDE_GITHUB_META_RANGES=1`), so a
  `git push` to someone else's repo is a complete exfiltration channel that looks
  like ordinary work.
- **The agent has passwordless sudo** and can simply switch the firewall off.
  Every container-internal firewall shares this, including Anthropic's.

What actually carries the weight is filesystem isolation: `~/.ssh`, `~/.aws` and
your dotfiles don't exist in here. The forwarded SSH agent and git credentials
are cleared in `containerEnv` for the same reason — push from the host, or use a
repo-scoped PAT. Prefer auto mode over `--dangerously-skip-permissions`; the docs
treat an isolation boundary as *required* only for the latter.

**For genuinely untrusted third-party code, use a VM or Claude Code on the web**,
which is [Anthropic's own recommendation](https://code.claude.com/docs/en/sandbox-environments#choose-an-approach).
A dev container is not the right tool for that job. And note that a malicious repo
can exfiltrate the agent credentials in `~/.claude` and `~/.codex`, which are
shared across your projects — use `${devcontainerId}`-scoped volume names if that
trade bothers you.

## Updating

| Bump | Where |
|---|---|
| pixi, Codex CLI, firewall (`CODEX_REF` + hashes) | `Dockerfile` args |
| Node | `NODE_VARIANT` in `devcontainer.json` |
| Claude Code | nothing; the Feature installs latest and it self-updates |

Bump `CODEX_REF` and rebuild — the `sha256sum` failure prints the hashes to
update. Don't fetch those scripts unpinned; they run as root with `NET_ADMIN`.

## Notes on a few non-obvious choices

Node base image, Python entirely from conda-forge — Node is only there to host
the two CLIs. `CLAUDE_CONFIG_DIR` is set because Claude Code keeps its OAuth
account in `~/.claude.json`, *outside* the `~/.claude` volume; without it you
re-authenticate on every rebuild. Node 22 because Codex requires 22+.
`--shm-size=16g` because Docker's 64 MB `/dev/shm` kills PyTorch DataLoader
workers. `.devcontainer/` is mounted read-only because an `initializeCommand`
added there would execute on your host at the next rebuild.

OpenAI's firewall rather than Anthropic's reference one: it has a genuine
`ip6tables` default-deny (the reference is IPv4-only, so an IPv6-enabled Docker
network walks straight past it) and no blanket outbound port-22 rule. Its
capability requirements are just `NET_ADMIN` and `NET_RAW` — the `SYS_ADMIN` and
`seccomp=unconfined` in OpenAI's own `devcontainer.secure.json` are for Codex's
inner bubblewrap sandbox, and are deliberately not copied here.