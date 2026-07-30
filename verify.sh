#!/usr/bin/env bash
# Smoke test for the dev container. Run INSIDE the container:
#
#   bash verify.sh
#
# Checks are grouped by layer, cheapest and most fundamental first, because a
# failure in an early layer explains every failure after it. Read the first
# FAIL, not the last.
#
# Read-only: touches nothing except two probe files it deletes.
# Delete this file once you trust the setup.

# Uses bash-only syntax. Re-exec if someone runs `sh verify.sh`.
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"

# Refuse to run on the host: every check would be measuring the wrong machine,
# and enough of them would pass to look plausible.
if [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ] && ! grep -qE 'docker|containerd|kubepods' /proc/1/cgroup 2>/dev/null; then
    printf '\033[31mThis is not the dev container.\033[0m verify.sh only means anything inside it:\n\n'
    printf '    devcontainer exec --workspace-folder . bash verify.sh\n\n'
    printf 'or run it from a VS Code terminal attached to the container.\n'
    exit 2
fi

pass=0; fail=0; skip=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no()   { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        -> %s\n' "$2"; fail=$((fail+1)); }
meh()  { printf '  \033[33mSKIP\033[0m  %s\n' "$1"; skip=$((skip+1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
head_ "1. Tooling"
# ---------------------------------------------------------------------------
node_major=$(node -v 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')
if [ "${node_major:-0}" -ge 22 ] 2>/dev/null; then
    ok "node $(node -v) (>=22 required by Codex)"
else
    no "node is ${node_major:-missing}, need >=22" "bump NODE_VARIANT in devcontainer.json"
fi

for bin in pixi codex claude git; do
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin on PATH ($("$bin" --version 2>&1 | head -1 | cut -c1-40))"
    else
        no "$bin not on PATH"
    fi
done

for s in /usr/local/bin/init-firewall.sh /usr/local/bin/post-start.sh; do
    [ -f "$s" ] && ok "$(basename "$s") present (fetched from openai/codex)" \
                || no "$(basename "$s") missing" "the pinned download or sha256 check failed at build"
done

# ---------------------------------------------------------------------------
head_ "2. Volume ownership  <- the failure that silently loses all agent state"
# ---------------------------------------------------------------------------
me="$(id -un)"
for d in "$HOME/.claude" "$HOME/.codex" "$HOME/.cache" /commandhistory; do
    if [ ! -d "$d" ]; then
        no "$d does not exist" "mount target does not match \$HOME ($HOME)"
    elif touch "$d/.probe" 2>/dev/null; then
        rm -f "$d/.probe"
        owner=$(stat -c '%U' "$d")
        if [ "$owner" = "$me" ]; then ok "$d writable"
        else ok "$d writable (owned by $owner; fine, $me can write)"; fi
    else
        no "$d not writable by $me" \
           "volume predates the Dockerfile install -d line: docker volume rm agents-claude agents-codex agents-history"
    fi
done

if [ -d .pixi ] && [ "$(stat -c '%U' .pixi)" = "$me" ]; then
    ok ".pixi owned by $me"
elif [ -d .pixi ]; then
    no ".pixi owned by $(stat -c '%U' .pixi)" "postCreateCommand chown did not run"
else
    no ".pixi missing" "pixi install did not run"
fi

# ---------------------------------------------------------------------------
head_ "3. Python environment"
# ---------------------------------------------------------------------------
py=$(command -v python 2>/dev/null)
case "$py" in
    *".pixi/envs/default/bin/python") ok "python resolves to the pixi env" ;;
    "")  no "no python on PATH" ;;
    *)   no "python resolves to $py" "PATH interpolation in containerEnv did not take effect" ;;
esac

# Guard against the containerEnv/remoteEnv mistake: if PATH lost the system
# directories, the container's own keep-alive `sleep` is gone too and it exits 0
# right after starting -- so you would not get this far. Check anyway.
for essential in sleep sh env; do
    command -v "$essential" >/dev/null 2>&1 \
        && ok "$essential on PATH" \
        || no "$essential NOT on PATH -- PATH is broken" \
              "PATH belongs in remoteEnv, not containerEnv: \${containerEnv:PATH} cannot resolve at container-create time"
done

# The check that matters for agents: they spawn non-interactive, non-login
# shells where .bashrc is never sourced.
if bash --noprofile --norc -c 'command -v python' 2>/dev/null | grep -q '.pixi/envs'; then
    ok "python visible in a non-interactive shell (agents will find it)"
else
    no "python NOT visible in a non-interactive shell" \
       "agents will hit 'command not found' or the wrong python; PATH must be in containerEnv, not .bashrc"
fi

python - <<'PY' 2>/dev/null && ok "python/numpy/torch import and versions match pixi.toml" \
                             || no "core imports failed or versions unexpected" "run: pixi install"
import sys, numpy, torch
assert sys.version_info[:2] >= (3, 13), sys.version
print(f"        python {sys.version.split()[0]}, numpy {numpy.__version__}, torch {torch.__version__}")
PY

# jaxtyping+beartype are only useful if they actually raise.
python - <<'PY' >/dev/null 2>&1 && ok "jaxtyping + beartype reject a wrong shape" \
                                || no "shape checking is not enforced" "annotations present but unchecked -- verify beartype is installed"
import torch
from jaxtyping import Float, jaxtyped
from beartype import beartype

@jaxtyped(typechecker=beartype)
def f(x: Float[torch.Tensor, "batch 4"]) -> Float[torch.Tensor, "batch 4"]:
    return x

f(torch.zeros(2, 4))
try:
    f(torch.zeros(2, 5))
    raise SystemExit(1)   # should have raised
except SystemExit:
    raise
except Exception:
    pass
PY

# ---------------------------------------------------------------------------
head_ "4. Container resources"
# ---------------------------------------------------------------------------
shm=$(df -B1 --output=size /dev/shm 2>/dev/null | tail -1 | tr -d ' ')
if [ "${shm:-0}" -gt 4000000000 ] 2>/dev/null; then
    ok "/dev/shm is $((shm/1024/1024/1024)) GB"
else
    no "/dev/shm is only $(( ${shm:-0} /1024/1024 )) MB" \
       "--shm-size=16g missing from runArgs; DataLoader(num_workers>0) will die"
fi

# The real test of shm: actually fork dataloader workers.
# Must be a real file with a __main__ guard: Python 3.14 changed the default
# multiprocessing start method on Linux from fork to forkserver (CPython
# gh-84559). forkserver re-imports __main__ in every worker, so piping the
# script via `python -` makes __main__ unimportable and the workers die.
_dl=$(mktemp /tmp/dl_check_XXXXXX.py)
cat > "$_dl" <<'DLEOF'
import torch
from torch.utils.data import DataLoader, TensorDataset

def main():
    ds = TensorDataset(torch.randn(64, 8))
    for _ in DataLoader(ds, batch_size=8, num_workers=2):
        pass

if __name__ == "__main__":
    main()
DLEOF
if python "$_dl" >/dev/null 2>&1; then
    ok "DataLoader with num_workers=2 runs (forks real workers)"
else
    no "DataLoader with num_workers>0 failed" \
       "check /dev/shm; on Python 3.14+ also ensure your entrypoint has an if __name__ guard, since forkserver re-imports it"
fi
rm -f "$_dl"

if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi -L >/dev/null 2>&1 && ok "nvidia-smi sees $(nvidia-smi -L | wc -l) GPU(s)" \
                                  || no "nvidia-smi present but no GPUs"
    if pixi run -e gpu python -c "import torch,sys; sys.exit(0 if torch.cuda.is_available() else 1)" >/dev/null 2>&1; then
        ok "torch.cuda.is_available() in the gpu environment"
    else
        no "gpu environment cannot see CUDA" "check the host NVIDIA Container Toolkit"
    fi
else
    meh "no GPU on this host (hostRequirements gpu:optional -- expected on a laptop)"
fi

# ---------------------------------------------------------------------------
head_ "5. Firewall"
# ---------------------------------------------------------------------------
reachable() { curl -s -o /dev/null --connect-timeout 6 "$1" 2>/dev/null; }

reachable https://example.com \
    && no "example.com is REACHABLE" "firewall is not active; check postStartCommand output" \
    || ok "example.com blocked (default-deny works)"

curl -s -o /dev/null -w '' --connect-timeout 8 https://api.anthropic.com 2>/dev/null \
    && ok "api.anthropic.com reachable" \
    || no "api.anthropic.com blocked" "Claude Code cannot work; check OPENAI_ALLOWED_DOMAINS"

reachable https://api.openai.com && ok "api.openai.com reachable" \
                                 || no "api.openai.com blocked" "Codex cannot work"

reachable https://conda.anaconda.org/ && ok "conda-forge reachable" \
                                      || no "conda-forge blocked" "pixi add will fail; re-run post-start.sh to re-resolve DNS"

curl -s -6 -o /dev/null --connect-timeout 6 https://example.com 2>/dev/null \
    && no "example.com reachable over IPv6" "the v6 allowlist bypass is open" \
    || ok "IPv6 blocked"

curl -s -o /dev/null --connect-timeout 3 http://169.254.169.254/ 2>/dev/null \
    && no "cloud metadata endpoint REACHABLE" "credential-theft path is open" \
    || ok "cloud metadata endpoint blocked"

# ---------------------------------------------------------------------------
head_ "6. Agent config persistence"
# ---------------------------------------------------------------------------
[ "$CLAUDE_CONFIG_DIR" = "$HOME/.claude" ] \
    && ok "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR (so .claude.json lands in the volume)" \
    || no "CLAUDE_CONFIG_DIR is '${CLAUDE_CONFIG_DIR:-unset}'" "you will re-authenticate on every rebuild"

[ "$CODEX_HOME" = "$HOME/.codex" ] && ok "CODEX_HOME=$CODEX_HOME" \
                                  || no "CODEX_HOME is '${CODEX_HOME:-unset}'"

case "$HISTFILE" in
    /commandhistory/*) ok "HISTFILE=$HISTFILE (shell history persists)" ;;
    *) no "HISTFILE is '${HISTFILE:-unset}'" "shell history will not survive a rebuild" ;;
esac

for v in SSH_AUTH_SOCK GH_TOKEN GITHUB_TOKEN; do
    [ -z "${!v}" ] && ok "$v is empty (no push credentials handed to agents)" \
                   || meh "$v is set -- intentional if you chose the convenience"
done

[ -f AGENTS.md ] && ok "AGENTS.md present" || no "AGENTS.md missing"
grep -q 'AGENTS.md' CLAUDE.md 2>/dev/null \
    && ok "CLAUDE.md imports AGENTS.md" \
    || no "CLAUDE.md does not import AGENTS.md" "Claude Code will ignore your instructions"

# ---------------------------------------------------------------------------
printf '\n\033[1mSummary:\033[0m %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
if [ "$fail" -gt 0 ]; then
    printf 'Fix the FIRST failure and re-run; later ones are often downstream.\n'
    exit 1
fi
printf 'Container looks healthy. Next: the manual checks in README (auth + resume across a rebuild).\n'
