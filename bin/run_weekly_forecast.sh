#!/bin/zsh
# Run the weekly forecast pipeline and render a report for review.
#
# Intended to be triggered by launchd on Wednesdays after 3 PM ET (see
# bin/org.epiforecasts.cityforecasts.plist), but can be run by hand, e.g. to
# reproduce a past forecast date:
#   FORECAST_DATE=2026-10-07 HUB_REF=<flu-metrocast SHA> bin/run_weekly_forecast.sh
#
# Env vars:
#   FORECAST_DATE  Wednesday forecast date, YYYY-MM-DD (default: most recent
#                  Wednesday in US Eastern time)
#   HUB_REF        flu-metrocast git ref to pull data from (default: main)
#   POLL_INTERVAL  seconds between checks for updated hub data (default: 600)
#   MAX_WAIT       max seconds to wait for updated hub data (default: 10800)
#   FORCE          set to 1 to run even if this week's forecast already exists

set -uo pipefail

# Keep the Mac awake for the whole run (data polling, fitting, rendering)
if [[ -z "${CAFFEINATED:-}" ]]; then
  export CAFFEINATED=1
  exec /usr/bin/caffeinate -i /bin/zsh "$0" "$@"
fi

REPO_DIR="${0:A:h:h}"
cd "$REPO_DIR" || exit 1

# launchd runs with a minimal environment
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"
# The renv library is not populated; use the system R library
export RENV_ACTIVATE_PROJECT=FALSE

export FORECAST_DATE="${FORECAST_DATE:-$(TZ=America/New_York date -v-wed +%F)}"
export HUB_REF="${HUB_REF:-main}"
POLL_INTERVAL="${POLL_INTERVAL:-600}"
MAX_WAIT="${MAX_WAIT:-10800}"
FORCE="${FORCE:-0}"

output_dir="output/cityforecasts/${FORECAST_DATE}"
reference_date=$(date -j -v+3d -f %F "$FORECAST_DATE" +%F)
output_file="${output_dir}/${reference_date}-epiforecasts-dyngam.parquet"

mkdir -p logs
LOG="logs/run_${FORECAST_DATE}_$(date +%Y%m%dT%H%M%S).log"
exec >>"$LOG" 2>&1

notify() {
  osascript -e "display notification \"$2\" with title \"cityforecasts: $1\"" \
    || true
}

fail() {
  echo "$(date): FAILED: $1"
  notify "run failed" "$1 (see $LOG)"
  exit 1
}

echo "$(date): starting run for forecast date $FORECAST_DATE (hub ref $HUB_REF)"

# Don't overwrite a forecast that has already been generated (e.g. by a
# manual run earlier in the day) unless FORCE=1
if [[ -f "$output_file" && "$FORCE" != "1" ]]; then
  echo "$(date): $output_file already exists, skipping (set FORCE=1 to rerun)"
  notify "skipped" "Forecast for $FORECAST_DATE already exists"
  exit 0
fi

# Wait for the hub data to be updated for this forecast date
waited=0
while true; do
  Rscript bin/check_data_ready.R
  check_status=$?
  case $check_status in
    0) break ;;
    1)
      if (( waited >= MAX_WAIT )); then
        fail "hub data not updated for $FORECAST_DATE after ${MAX_WAIT}s"
      fi
      echo "$(date): data not ready, checking again in ${POLL_INTERVAL}s"
      sleep "$POLL_INTERVAL"
      (( waited += POLL_INTERVAL ))
      ;;
    2) fail "hub data is newer than $FORECAST_DATE; set HUB_REF" ;;
    *) fail "data check errored (exit $check_status)" ;;
  esac
done

# Fit models and generate forecasts
Rscript -e 'targets::tar_make()' \
  || fail "targets::tar_make() errored"

# error = "null" lets individual targets fail without stopping the pipeline,
# so report any errored targets
errored=$(Rscript -e 'cat(targets::tar_errored(), sep = " ")')
[ -f "$output_file" ]] || fail "no forecast file at $output_file"

# Render plots of the forecasts for review as markdown + PNGs, which GitHub
# renders natively (including on mobile)
Rscript -e "rmarkdown::render('weekly_forecasts.Rmd',
  output_format = rmarkdown::github_document(html_preview = FALSE),
  output_file = 'review.md', output_dir = '${output_dir}')" \
  || fail "rendering weekly_forecasts.Rmd errored"
# rmarkdown writes absolute figure paths when output_dir is elsewhere; make
# them relative so they display on GitHub
sed -i '' "s|${REPO_DIR}/${output_dir}/||g" "${output_dir}/review.md"

if [[ -n "$errored" ]]; then
  echo "$(date): finished with errored targets: $errored"
  notify "ready with errors" \
    "Forecasts for $FORECAST_DATE ready, but targets errored: $errored"
else
  echo "$(date): finished successfully"
  notify "ready for review" "Forecasts for $FORECAST_DATE ready for review"
fi
