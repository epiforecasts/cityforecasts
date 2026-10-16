#!/usr/bin/env bash
# Open a PR into the flu-metrocast hub submitting the forecast for a forecast
# date, following the manual workflow:
#   1. clone our fork of the hub and bring it up to date with the hub
#   2. copy the forecast file into model-output/<model id>/
#   3. commit and push it to the fork
#   4. open a PR from the fork into the hub
# Each forecast goes on its own branch off the hub's main, rather than the
# fork's main, so the fork's main can be used for other PRs to the hub and
# there's no need to wait for one week's PR to merge before the next.
#
# Run by .github/workflows/submit-to-hub.yaml when forecasts are merged into
# main, but can also be run locally, e.g.:
#   FORECAST_DATE=2026-11-04 bin/submit_to_hub.sh
#
# Env vars:
#   FORECAST_DATE  Wednesday forecast date, YYYY-MM-DD (required)
#   HUB_TOKEN      token that can push to HUB_FORK and open PRs into HUB_REPO
#                  (default: GH_TOKEN, then the gh CLI's login)
#   HUB_REPO       hub repo (default: reichlab/flu-metrocast)
#   HUB_FORK       fork of the hub to push the branch to
#                  (default: kaitejohnson/flu-metrocast)
#   MODEL_ID       hub model id (default: epiforecasts-dyngam)
#   PAGES_URL      GitHub Pages URL the report is published under
#                  (default: https://epiforecasts.io/cityforecasts)
#   DRY_RUN        set to 1 to commit locally but not push or open a PR

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR" || exit 1

HUB_REPO="${HUB_REPO:-reichlab/flu-metrocast}"
HUB_FORK="${HUB_FORK:-kaitejohnson/flu-metrocast}"
MODEL_ID="${MODEL_ID:-epiforecasts-dyngam}"
pages_url="${PAGES_URL:-https://epiforecasts.io/cityforecasts}"

# Write a message to the GitHub Actions job summary, if running there
summarise() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "$1" >>"$GITHUB_STEP_SUMMARY"
  fi
}

fail() {
  echo "$(date): FAILED: $1"
  summarise "Hub submission for ${FORECAST_DATE:-unknown date} failed: $1"
  exit 1
}

[[ -n "${FORECAST_DATE:-}" ]] || fail "FORECAST_DATE is not set"
[[ "$FORECAST_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
  || fail "FORECAST_DATE must be YYYY-MM-DD, got $FORECAST_DATE"

if [[ -n "${HUB_TOKEN:-}" ]]; then
  export GH_TOKEN="$HUB_TOKEN"
fi
token="${GH_TOKEN:-$(gh auth token 2>/dev/null)}"
[[ -n "$token" || "${DRY_RUN:-0}" == "1" ]] \
  || fail "no token to push to $HUB_FORK; set HUB_TOKEN"

output_dir="output/cityforecasts/${FORECAST_DATE}"
forecast_file=$(ls "${output_dir}"/*-"${MODEL_ID}".parquet 2>/dev/null | head -n 1)
[[ -n "$forecast_file" ]] || fail "no forecast file in $output_dir"
file_name=$(basename "$forecast_file")
reference_date="${file_name%%-"${MODEL_ID}".parquet}"
hub_path="model-output/${MODEL_ID}/${file_name}"
branch="${MODEL_ID}-${reference_date}"
fork_owner="${HUB_FORK%%/*}"

echo "$(date): submitting $forecast_file to $HUB_REPO as $hub_path"

# 1. Clone the fork and branch off the hub's latest main
clone_dir="$(mktemp -d)/flu-metrocast"
git clone -q "https://x-access-token:${token}@github.com/${HUB_FORK}.git" \
  "$clone_dir" || fail "could not clone $HUB_FORK"
git -C "$clone_dir" remote add upstream "https://github.com/${HUB_REPO}.git"
git -C "$clone_dir" fetch -q upstream main \
  || fail "could not fetch $HUB_REPO main"
git -C "$clone_dir" checkout -q -B "$branch" upstream/main

# 2. Copy the forecast into the model output folder
mkdir -p "${clone_dir}/model-output/${MODEL_ID}"
cp "$forecast_file" "${clone_dir}/${hub_path}"

# 3. Commit and push to the fork
git -C "$clone_dir" add "$hub_path"
if git -C "$clone_dir" diff --cached --quiet; then
  rm -rf "$clone_dir"
  echo "$(date): $hub_path is already on $HUB_REPO main, nothing to submit"
  summarise "Skipped: \`$hub_path\` is already on \`$HUB_REPO\` main"
  exit 0
fi
git -C "$clone_dir" commit -q -m "${MODEL_ID} forecasts for ${FORECAST_DATE}" \
  || fail "git commit failed"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "$(date): dry run, not pushing. Commit is in $clone_dir:"
  git -C "$clone_dir" show --stat --oneline HEAD
  exit 0
fi
git -C "$clone_dir" push -q --force origin "$branch" \
  || fail "git push to $HUB_FORK failed"
rm -rf "$clone_dir"
echo "$(date): pushed $branch to $HUB_FORK"

if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
  run_line="- Workflow run: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
else
  run_line="- Submitted locally from $(hostname)"
fi
pr_body="Forecasts from \`${MODEL_ID}\` for forecast date ${FORECAST_DATE} (reference date ${reference_date}).

- Report: ${pages_url}/${FORECAST_DATE}/
- Source: https://github.com/epiforecasts/cityforecasts/tree/main/${output_dir}
${run_line}"

# 4. Open a PR into the hub. On a resubmission the force push above updates
# the existing PR
existing_pr=$(gh pr list -R "$HUB_REPO" --state open --head "$branch" \
  --json number,headRepositoryOwner \
  --jq "map(select(.headRepositoryOwner.login == \"${fork_owner}\")) | .[0].number // empty" \
  2>/dev/null)
if [[ -n "$existing_pr" ]]; then
  echo "$(date): updated existing PR #$existing_pr on $HUB_REPO"
  summarise "Updated hub PR: https://github.com/${HUB_REPO}/pull/${existing_pr}"
  exit 0
fi
pr_url=$(gh pr create -R "$HUB_REPO" --base main \
  --head "${fork_owner}:${branch}" \
  --title "${FORECAST_DATE} ${MODEL_ID}" --body "$pr_body") \
  || fail "could not open PR into $HUB_REPO"
echo "$(date): opened PR $pr_url"
summarise "Opened hub PR: $pr_url"
