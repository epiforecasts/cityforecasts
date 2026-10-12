#!/usr/bin/env bash
# Run the weekly forecast pipeline, render a report for review and push the
# outputs to a forecast/<date> branch.
#
# Run on a schedule by .github/workflows/weekly-forecast.yaml, but can also be
# run locally (macOS or Linux), e.g. to reproduce a past forecast date:
#   FORECAST_DATE=2026-10-07 HUB_REF=<flu-metrocast SHA> bin/run_weekly_forecast.sh
#
# Env vars:
#   FORECAST_DATE  Wednesday forecast date, YYYY-MM-DD (default: most recent
#                  Wednesday in US Eastern time)
#   HUB_REF        flu-metrocast git ref to pull data from (default: main)
#   POLL_INTERVAL  seconds between checks for updated hub data (default: 600)
#   MAX_WAIT       max seconds to wait for updated hub data (default: 10800)
#   FORCE          set to 1 to run even if this week's forecast already exists
#   PUSH           set to 0 to skip pushing outputs to GitHub (default: 1)

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR" || exit 1

# The renv library is not populated; use the system R library
export RENV_ACTIVATE_PROJECT=FALSE

# Add days to a YYYY-MM-DD date with either GNU (Linux) or BSD (macOS) date
date_add() {
  if date --version >/dev/null 2>&1; then
    date -d "$1 $2 days" +%F
  else
    date -j -v"${2}"d -f %F "$1" +%F
  fi
}

# Most recent Wednesday (today if Wednesday) in US Eastern time
default_forecast_date() {
  local today dow
  today=$(TZ=America/New_York date +%F)
  dow=$(TZ=America/New_York date +%u) # Monday = 1
  date_add "$today" "-$(( (dow - 3 + 7) % 7 ))"
}

export FORECAST_DATE="${FORECAST_DATE:-$(default_forecast_date)}"
export HUB_REF="${HUB_REF:-main}"
POLL_INTERVAL="${POLL_INTERVAL:-600}"
MAX_WAIT="${MAX_WAIT:-10800}"
FORCE="${FORCE:-0}"
PUSH="${PUSH:-1}"

output_dir="output/cityforecasts/${FORECAST_DATE}"
reference_date=$(date_add "$FORECAST_DATE" +3)
output_file="${output_dir}/${reference_date}-epiforecasts-dyngam.parquet"
branch="forecast/${FORECAST_DATE}"
review_url="https://github.com/epiforecasts/cityforecasts/blob/${branch}/${output_dir}/review.md"

# Write a message to the GitHub Actions job summary, if running there
summarise() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "$1" >>"$GITHUB_STEP_SUMMARY"
  fi
}

fail() {
  echo "$(date): FAILED: $1"
  summarise "Forecast run for $FORECAST_DATE failed: $1"
  exit 1
}

echo "$(date): starting run for forecast date $FORECAST_DATE (hub ref $HUB_REF)"

# Don't overwrite a forecast that has already been generated (e.g. by a
# manual run earlier in the day) unless FORCE=1: skip if the parquet exists in
# the working tree (i.e. locally, or on main when run on GitHub Actions) or on
# the forecast/<date> branch on GitHub
if [[ "$FORCE" != "1" ]]; then
  if [[ -f "$output_file" ]]; then
    echo "$(date): $output_file already exists, skipping (set FORCE=1 to rerun)"
    summarise "Skipped: \`$output_file\` already exists"
    exit 0
  fi
  if git fetch -q origin "$branch" 2>/dev/null \
    && git cat-file -e "FETCH_HEAD:$output_file" 2>/dev/null; then
    echo "$(date): $output_file already exists on $branch, skipping (set FORCE=1 to rerun)"
    summarise "Skipped: \`$output_file\` already exists on \`$branch\` ([review report]($review_url))"
    exit 0
  fi
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
[[ -f "$output_file" ]] || fail "no forecast file at $output_file"

# Render plots of the forecasts for review as markdown + PNGs, which GitHub
# renders natively (including on mobile)
Rscript -e "rmarkdown::render('weekly_forecasts.Rmd',
  output_format = rmarkdown::github_document(html_preview = FALSE),
  output_file = 'review.md', output_dir = '${output_dir}')" \
  || fail "rendering weekly_forecasts.Rmd errored"
# rmarkdown writes absolute figure paths when output_dir is elsewhere; make
# them relative so they display on GitHub
sed -i.bak "s|${REPO_DIR}/${output_dir}/||g" "${output_dir}/review.md" \
  && rm "${output_dir}/review.md.bak"

if [[ "$PUSH" == "1" ]]; then
  # Commit the outputs and review report to a forecast/<date> branch off
  # origin/main and push it for review. Uses a temporary worktree so the
  # checked-out branch is untouched. Outputs are gitignored, hence add -f;
  # hooks are skipped since this commit only contains generated files.
  worktree="$(mktemp -d)/cityforecasts"
  cleanup_worktree() {
    git worktree remove --force "$worktree" 2>/dev/null
    git worktree prune
  }
  git fetch origin main || fail "git fetch failed"
  git worktree add -B "$branch" "$worktree" origin/main \
    || fail "could not create worktree for $branch"
  mkdir -p "${worktree}/${output_dir}"
  cp -R "${output_dir}/config.yaml" "$output_file" "${output_dir}/review.md" \
    "${output_dir}/review_files" "${worktree}/${output_dir}/"
  git -C "$worktree" add -f "$output_dir"
  git -C "$worktree" commit --no-verify -q \
    -m "Forecasts for ${FORECAST_DATE} (hub ref ${HUB_REF})" \
    || { cleanup_worktree; fail "git commit failed"; }
  git -C "$worktree" push --force -u origin "$branch" \
    || { cleanup_worktree; fail "git push failed"; }
  cleanup_worktree
  echo "$(date): pushed to $branch, review at $review_url"
  summarise "Forecasts for $FORECAST_DATE pushed to \`$branch\`: [review report]($review_url)"
fi

if [[ -n "$errored" ]]; then
  echo "$(date): finished with errored targets: $errored"
  summarise "**Errored targets:** $errored"
  [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::warning::Errored targets: $errored"
fi
echo "$(date): finished"
