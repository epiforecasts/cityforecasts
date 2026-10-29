#!/usr/bin/env bash
# Render a report of a forecast from its parquet in
# output/cityforecasts/<forecast date>/ (forecast_report.Rmd) and publish it to
# GitHub Pages, so forecasts generated outside the weekly forecast workflow
# (e.g. run locally and merged into main) also get a report.
#
# Run by .github/workflows/publish-report.yaml when a forecast is merged into
# main, but can also be run locally:
#   FORECAST_DATE=2026-10-28 bin/publish_forecast_report.sh
#
# Env vars:
#   FORECAST_DATE  Wednesday forecast date, YYYY-MM-DD (required)
#   HUB_REF        flu-metrocast git ref to pull data from (default: main)
#   FORCE          set to 1 to replace an existing report for this date, e.g.
#                  one published by bin/run_weekly_forecast.sh (default: 0)
#   PUSH           set to 0 to only render the report (default: 1)
#   PAGES_URL      GitHub Pages URL the report is published under
#                  (default: https://epiforecasts.io/cityforecasts)

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR" || exit 1

# The renv library is not populated; use the system R library
export RENV_ACTIVATE_PROJECT=FALSE

: "${FORECAST_DATE:?set FORECAST_DATE}"
HUB_REF="${HUB_REF:-main}"
FORCE="${FORCE:-0}"
PUSH="${PUSH:-1}"
report_url="${PAGES_URL:-https://epiforecasts.io/cityforecasts}/${FORECAST_DATE}/"

summarise() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "$1" >>"$GITHUB_STEP_SUMMARY"
  fi
}

# Don't replace a report already published for this date (e.g. the one from
# the weekly forecast workflow, which also shows the model fit) unless FORCE=1
if [[ "$PUSH" == "1" && "$FORCE" != "1" ]] \
  && git fetch -q origin gh-pages 2>/dev/null \
  && git cat-file -e "FETCH_HEAD:${FORECAST_DATE}/index.html" 2>/dev/null; then
  echo "$(date): report for $FORECAST_DATE already published, skipping (set FORCE=1 to replace)"
  summarise "Skipped: [report for $FORECAST_DATE]($report_url) already published"
  exit 0
fi

out_dir="$(mktemp -d)"
Rscript -e "rmarkdown::render('forecast_report.Rmd',
  output_format = rmarkdown::html_document(fig_retina = 1),
  output_file = 'report.html', output_dir = '${out_dir}',
  intermediates_dir = '${out_dir}', knit_root_dir = '${REPO_DIR}',
  params = list(forecast_date = '${FORECAST_DATE}', hub_ref = '${HUB_REF}'))" \
  || { echo "$(date): FAILED: rendering forecast_report.Rmd errored"; exit 1; }

if [[ "$PUSH" == "1" ]]; then
  bin/publish_report.sh "$FORECAST_DATE" "${out_dir}/report.html" || exit 1
  echo "$(date): published report at $report_url"
  summarise "Published [report for $FORECAST_DATE]($report_url)"
else
  echo "$(date): report at ${out_dir}/report.html"
fi
