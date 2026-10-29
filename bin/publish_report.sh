#!/usr/bin/env bash
# Publish a forecast report to GitHub Pages (gh-pages branch) at
# <forecast date>/index.html, with an index page linking to all reports. The
# branch is pushed as a single commit each time so old report versions don't
# accumulate in the repo history.
#
# Usage: bin/publish_report.sh <forecast date> <report.html>
#
# Used by bin/run_weekly_forecast.sh and bin/publish_forecast_report.sh.

set -uo pipefail

forecast_date="$1"
report="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR" || exit 1

worktree="$(mktemp -d)/gh-pages"
cleanup_worktree() {
  git worktree remove --force "$worktree" 2>/dev/null
  git worktree prune
}
fail() {
  echo "$(date): FAILED: $1"
  cleanup_worktree
  exit 1
}

if git fetch -q origin gh-pages 2>/dev/null; then
  git worktree add --detach "$worktree" FETCH_HEAD \
    || fail "could not create worktree for gh-pages"
else
  git fetch -q origin main || fail "git fetch failed"
  git worktree add --detach "$worktree" origin/main \
    || fail "could not create worktree for gh-pages"
  git -C "$worktree" rm -rqf .
fi
mkdir -p "${worktree}/${forecast_date}"
cp "$report" "${worktree}/${forecast_date}/index.html"
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
  -m "Reports as of ${forecast_date}") \
  || fail "could not create gh-pages commit"
git -C "$worktree" push --force origin "${pages_commit}:refs/heads/gh-pages" \
  || fail "git push to gh-pages failed"
cleanup_worktree
