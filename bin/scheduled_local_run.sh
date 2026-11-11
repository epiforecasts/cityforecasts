#!/usr/bin/env bash
# Run the weekly forecast from a clean copy of origin/main, for the local
# launchd schedule (see bin/install_local_schedule.sh). Can also be run by
# hand to do exactly what the scheduled run does:
#   bin/scheduled_local_run.sh
#
# Runs in a separate git worktree (default ../cityforecasts-scheduled), reset
# to origin/main each time, so it always uses the merged code and never
# touches the main clone's working files. The worktree sits next to this
# repo, so the California data in ../flu_metrocast_california_data is found.
#
# Any env vars for bin/run_weekly_forecast.sh (e.g. FORECAST_DATE, FORCE)
# are passed through. Also:
#   CITYFORECASTS_REPO  path of the main clone (default: this script's repo;
#                       set by the launchd job, which runs a copy of this
#                       script)
#   SCHEDULED_WORKTREE  path of the worktree to run in
#
# Logs go to logs/scheduled_<timestamp>.log in the main clone, and a macOS
# notification is shown when the run finishes.

set -uo pipefail

REPO_DIR="${CITYFORECASTS_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
WORKTREE="${SCHEDULED_WORKTREE:-$(dirname "$REPO_DIR")/cityforecasts-scheduled}"
mkdir -p "$REPO_DIR/logs"
log="$REPO_DIR/logs/scheduled_$(date +%Y%m%dT%H%M%S).log"

notify() {
  osascript -e "display notification \"$1\" with title \"cityforecasts\"" \
    2>/dev/null || true
}

{
  echo "$(date): scheduled run in $WORKTREE"
  git -C "$REPO_DIR" fetch -q origin main || {
    echo "git fetch failed"
    exit 1
  }
  if [[ ! -d "$WORKTREE" ]]; then
    git -C "$REPO_DIR" worktree add -q --detach "$WORKTREE" origin/main ||
      exit 1
  fi
  # Reset to origin/main and start from an empty targets store, as in CI
  git -C "$WORKTREE" checkout -q --detach -f origin/main || exit 1
  rm -rf "$WORKTREE/_targets"
  echo "$(date): at origin/main $(git -C "$WORKTREE" rev-parse --short HEAD)"

  MAX_WAIT="${MAX_WAIT:-14400}" "$WORKTREE/bin/run_weekly_forecast.sh"
} >"$log" 2>&1
status=$?

if [[ $status -eq 0 ]]; then
  notify "Weekly forecast run finished. Log: $log"
else
  notify "Weekly forecast run FAILED (exit $status). Log: $log"
fi
exit $status
