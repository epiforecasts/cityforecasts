#!/usr/bin/env bash
# Run the weekly forecast pipeline, push the outputs to a forecast/<date>
# branch, publish a report for review to GitHub Pages and open a PR of the
# forecast branch into main linking to the report.
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
#   OPEN_PR        set to 0 to skip opening a PR into main (default: 1);
#                  requires the gh CLI to be installed and authenticated
#   PR_REVIEWER    GitHub user to request a review of the PR from
#                  (default: none)
#   PAGES_URL      GitHub Pages URL the report is published under
#                  (default: https://epiforecasts.io/cityforecasts)

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
OPEN_PR="${OPEN_PR:-1}"

output_dir="output/cityforecasts/${FORECAST_DATE}"
reference_date=$(date_add "$FORECAST_DATE" +3)
output_file="${output_dir}/${reference_date}-epiforecasts-dyngam.parquet"
branch="forecast/${FORECAST_DATE}"
pages_url="${PAGES_URL:-https://epiforecasts.io/cityforecasts}"
report_url="${pages_url}/${FORECAST_DATE}/"

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
    summarise "Skipped: \`$output_file\` already exists on \`$branch\` ([review report]($report_url))"
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

# Render plots of the forecasts for review as a single self-contained HTML
# file (standard resolution figures keep it to ~5 MB)
report="${output_dir}/report.html"
Rscript -e "rmarkdown::render('weekly_forecasts.Rmd',
  output_format = rmarkdown::html_document(fig_retina = 1),
  output_file = 'report.html', output_dir = '${output_dir}')" \
  || fail "rendering weekly_forecasts.Rmd errored"

if [[ "$PUSH" == "1" ]]; then
  git fetch origin main || fail "git fetch failed"

  # Commit the config and forecasts to a forecast/<date> branch off
  # origin/main and push it. Uses a temporary worktree so the checked-out
  # branch is untouched. Outputs are gitignored, hence add -f; hooks are
  # skipped since this commit only contains generated files.
  worktree="$(mktemp -d)/cityforecasts"
  cleanup_worktree() {
    git worktree remove --force "$worktree" 2>/dev/null
    git worktree prune
  }
  git worktree add -B "$branch" "$worktree" origin/main \
    || fail "could not create worktree for $branch"
  mkdir -p "${worktree}/${output_dir}"
  cp "${output_dir}/config.yaml" "$output_file" "${worktree}/${output_dir}/"
  git -C "$worktree" add -f "$output_dir"
  git -C "$worktree" commit --no-verify -q \
    -m "Forecasts for ${FORECAST_DATE} (hub ref ${HUB_REF})" \
    || { cleanup_worktree; fail "git commit failed"; }
  git -C "$worktree" push --force -u origin "$branch" \
    || { cleanup_worktree; fail "git push failed"; }
  cleanup_worktree
  echo "$(date): pushed forecasts to $branch"

  # Publish the report to GitHub Pages (gh-pages branch) at
  # <date>/index.html, with an index page linking to all reports. The branch
  # is pushed as a single commit each time so old report versions don't
  # accumulate in the repo history.
  worktree="$(mktemp -d)/gh-pages"
  if git fetch -q origin gh-pages 2>/dev/null; then
    git worktree add --detach "$worktree" FETCH_HEAD \
      || fail "could not create worktree for gh-pages"
  else
    git worktree add --detach "$worktree" origin/main \
      || fail "could not create worktree for gh-pages"
    git -C "$worktree" rm -rqf .
  fi
  mkdir -p "${worktree}/${FORECAST_DATE}"
  cp "$report" "${worktree}/${FORECAST_DATE}/index.html"
  touch "${worktree}/.nojekyll"
  {
    echo '<!DOCTYPE html><html><head><meta charset="utf-8">'
    echo '<meta name="viewport" content="width=device-width, initial-scale=1">'
    echo '<title>cityforecasts reports</title>'
    echo '<style>body{font-family:system-ui,sans-serif;max-width:40em;margin:2em auto;padding:0 1em;line-height:1.6}</style>'
    echo '</head><body><h1>cityforecasts weekly reports</h1><ul>'
    for d in $(cd "$worktree" && ls -d 20??-??-?? | sort -r); do
      echo "<li><a href=\"${d}/\">${d}</a></li>"
    done
    echo '</ul></body></html>'
  } >"${worktree}/index.html"
  git -C "$worktree" add -A
  pages_commit=$(git -C "$worktree" commit-tree "$(git -C "$worktree" write-tree)" \
    -m "Reports as of ${FORECAST_DATE}") \
    || { cleanup_worktree; fail "could not create gh-pages commit"; }
  git -C "$worktree" push --force origin "${pages_commit}:refs/heads/gh-pages" \
    || { cleanup_worktree; fail "git push to gh-pages failed"; }
  cleanup_worktree
  echo "$(date): published report at $report_url"
  summarise "Forecasts for $FORECAST_DATE: [review report]($report_url), forecasts on branch \`$branch\`"

  # Open a PR of the forecast branch into main pointing to the report. The
  # report stays at its dated URL on GitHub Pages, so past reports can be
  # reviewed from the PRs or the index page. On a rerun (FORCE=1) the
  # existing PR is updated instead.
  if [[ "$OPEN_PR" == "1" ]]; then
    if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
      run_line="- Workflow run: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
    else
      run_line="- Run locally on $(hostname)"
    fi
    if [[ -n "$errored" ]]; then
      errored_line="- **Errored targets:** \`${errored}\`"
    else
      errored_line="- Errored targets: none"
    fi
    pr_body="Forecasts for **${FORECAST_DATE}** (reference date ${reference_date}).

**[Review report](${report_url})** (all past reports: ${pages_url}/)

- Hub ref: \`${HUB_REF}\`
${run_line}
${errored_line}

Merging this PR archives the forecast on main and opens a PR submitting it to the flu-metrocast hub."
    existing_pr=$(gh pr list --head "$branch" --base main --state open \
      --json number --jq '.[0].number' 2>/dev/null)
    if [[ -n "$existing_pr" ]]; then
      # gh api rather than gh pr edit, which errors on some gh versions
      if gh api -X PATCH "repos/{owner}/{repo}/pulls/${existing_pr}" \
        -f body="$pr_body" >/dev/null; then
        echo "$(date): updated PR #$existing_pr"
        summarise "Updated PR #$existing_pr"
      else
        echo "::warning::could not update PR #$existing_pr"
      fi
    elif pr_url=$(gh pr create --base main --head "$branch" \
      --title "Forecasts for ${FORECAST_DATE}" --body "$pr_body"); then
      echo "$(date): opened PR $pr_url"
      summarise "Opened PR: $pr_url"
      if [[ -n "${PR_REVIEWER:-}" ]] \
        && ! gh api -X POST "repos/{owner}/{repo}/pulls/${pr_url##*/}/requested_reviewers" \
          -f "reviewers[]=$PR_REVIEWER" >/dev/null; then
        echo "::warning::could not request a review from $PR_REVIEWER"
      fi
    else
      # Don't fail the run: the forecasts and report are already pushed
      echo "$(date): could not open PR for $branch"
      summarise "**Could not open PR** for \`$branch\`; open it manually"
      [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::warning::Could not open PR for $branch"
    fi
  fi
else
  echo "$(date): report at ${REPO_DIR}/${report}"
fi

if [[ -n "$errored" ]]; then
  echo "$(date): finished with errored targets: $errored"
  summarise "**Errored targets:** $errored"
  [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::warning::Errored targets: $errored"
fi
echo "$(date): finished"
