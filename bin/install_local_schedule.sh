#!/usr/bin/env bash
# Install (or update) a macOS launchd job that runs bin/scheduled_local_run.sh
# every week, replacing the GitHub Actions schedule (which can't access the
# private California data).
#
# Usage:
#   bin/install_local_schedule.sh [weekday] [hour]
#   bin/install_local_schedule.sh --uninstall
#
#   weekday  day of the week to run, e.g. wednesday (default) or thursday
#   hour     hour of the day to run, in the Mac's local time zone (default
#            20, i.e. 20:00 UK time = 3 PM US Eastern, as the UK and US
#            change clocks within a few weeks of each other)
#
# Rerun with a different weekday to change the schedule, e.g. to move a single
# week to Thursday and back again afterwards.
#
# launchd runs the job at the scheduled time if the Mac is awake, or as soon
# as it wakes if it was asleep. It doesn't run if the Mac was shut down.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="io.epiforecasts.cityforecasts.weekly"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
# The job runs a copy of the runner script, so it keeps working whichever
# branch the main clone has checked out
RUNNER_DIR="$HOME/Library/Application Support/cityforecasts"
RUNNER="$RUNNER_DIR/scheduled_local_run.sh"
DOMAIN="gui/$(id -u)"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$RUNNER"
  echo "Removed $LABEL"
  exit 0
fi

weekday_name=$(echo "${1:-wednesday}" | tr '[:upper:]' '[:lower:]')
hour="${2:-20}"
case "$weekday_name" in
  sunday) weekday=0 ;;
  monday) weekday=1 ;;
  tuesday) weekday=2 ;;
  wednesday) weekday=3 ;;
  thursday) weekday=4 ;;
  friday) weekday=5 ;;
  saturday) weekday=6 ;;
  *)
    echo "Unknown weekday: $1" >&2
    exit 1
    ;;
esac

# launchd jobs get a minimal PATH, so include where Rscript, gh and git live
path="$(dirname "$(command -v Rscript)"):$(dirname "$(command -v gh)")"
path="${path}:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$(dirname "$PLIST")" "$REPO_DIR/logs" "$RUNNER_DIR"
cp "$REPO_DIR/bin/scheduled_local_run.sh" "$RUNNER"
chmod +x "$RUNNER"
cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${RUNNER}</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key>
    <integer>${weekday}</integer>
    <key>Hour</key>
    <integer>${hour}</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${path}</string>
    <key>CITYFORECASTS_REPO</key>
    <string>${REPO_DIR}</string>
  </dict>
  <key>StandardOutPath</key>
  <string>${REPO_DIR}/logs/launchd.log</string>
  <key>StandardErrorPath</key>
  <string>${REPO_DIR}/logs/launchd.log</string>
</dict>
</plist>
EOF

# Reload so changes to the schedule take effect
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Scheduled $LABEL: every ${weekday_name} at ${hour}:00 local time ($(date +%Z))"
echo "Run it now with: launchctl kickstart $DOMAIN/$LABEL"
