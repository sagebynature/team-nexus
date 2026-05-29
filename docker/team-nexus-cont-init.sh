#!/command/with-contenv sh
# shellcheck shell=sh
set -eu

# Team Nexus bootstrap layer for the upstream Hermes s6-overlay image.
#
# This runs as an s6 cont-init hook after the upstream Hermes stage2 setup has
# remapped/chowned the hermes user. Keep it idempotent: it runs on every
# container start before the Compose command is routed through main-wrapper.sh.

HERMES_HOME="${HERMES_HOME:-/opt/data}"
HERMES_KANBAN_HOME="${HERMES_KANBAN_HOME:-}"
HERMES_VENV_BIN="${HERMES_VENV_BIN:-/opt/hermes/.venv/bin/hermes}"
HERMES_USER_HOME="$(getent passwd hermes 2>/dev/null | cut -d: -f6 || true)"
HERMES_USER_HOME="${HERMES_USER_HOME:-/opt/data}"

if [ -n "$HERMES_HOME" ]; then
  mkdir -p "$HERMES_HOME/.local/bin" "$HERMES_HOME/skills/.hub"
  # Hermes doctor still checks Path.home()/.local/bin even when HERMES_HOME
  # points at a profile directory. In this Docker image the hermes user's HOME
  # is /opt/data, so keep both the active profile shim and the user-home shim.
  mkdir -p "$HERMES_USER_HOME/.local/bin"

  if [ -x "$HERMES_VENV_BIN" ]; then
    ln -sfn "$HERMES_VENV_BIN" "$HERMES_HOME/.local/bin/hermes"
    ln -sfn "$HERMES_VENV_BIN" "$HERMES_USER_HOME/.local/bin/hermes"
  fi

  # `hermes skills list` normally initializes this. Creating the minimal lock
  # file here avoids every freshly cloned agent home reporting an uninitialized
  # Skills Hub before any hub skills have been installed.
  if [ ! -f "$HERMES_HOME/skills/.hub/lock.json" ]; then
    printf '{"installed":{}}\n' > "$HERMES_HOME/skills/.hub/lock.json"
  fi

  # The upstream entrypoint also fixes ownership, but these paths are created by
  # this hook and should be writable after main-wrapper drops privileges.
  chown -hR hermes:hermes "$HERMES_HOME/.local" "$HERMES_HOME/skills/.hub" "$HERMES_USER_HOME/.local" 2>/dev/null || true
fi

if [ -n "$HERMES_KANBAN_HOME" ]; then
  # Shared writable Kanban root for the whole Team Nexus Compose stack.
  # Hermes initializes the SQLite schema lazily; this hook just ensures the
  # mounted directory exists and remains writable after privilege drop.
  mkdir -p "$HERMES_KANBAN_HOME"
  chown -hR hermes:hermes "$HERMES_KANBAN_HOME" 2>/dev/null || true
fi

TEAM_NEXUS_ARTIFACTS_DIR="${TEAM_NEXUS_ARTIFACTS_DIR:-/shared/project/artifacts}"
if [ -n "$TEAM_NEXUS_ARTIFACTS_DIR" ]; then
  # Cross-agent handoff artifacts are the only writable submount under the
  # otherwise read-only /shared/project tree. If Compose created the bind source
  # on a fresh checkout, normalize ownership before main-wrapper drops
  # privileges.
  mkdir -p "$TEAM_NEXUS_ARTIFACTS_DIR" 2>/dev/null || true
  if [ -d "$TEAM_NEXUS_ARTIFACTS_DIR" ]; then
    chown -hR hermes:hermes "$TEAM_NEXUS_ARTIFACTS_DIR" 2>/dev/null || true
  fi
fi

echo "[team-nexus] cont-init bootstrap complete for HERMES_HOME=$HERMES_HOME"
