#!/usr/bin/env bash
# Build the web export and publish it to the gh-pages branch (GitHub Pages).
#   tools/deploy_web.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
godot --headless --path game --import >/dev/null 2>&1 || true
godot --headless --path game --export-release Web ../build/web/index.html
TMP="$(mktemp -d)"
git worktree add -f "$TMP" gh-pages 2>/dev/null || git worktree add -f --orphan -b gh-pages "$TMP"
find "$TMP" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R build/web/. "$TMP/"
touch "$TMP/.nojekyll"
ID=$(gh api user -q .id); L=$(gh api user -q .login)
git -C "$TMP" add -A
git -C "$TMP" -c user.name="$L" -c user.email="$ID+$L@users.noreply.github.com" \
  commit -q -m "Deploy web build $(git rev-parse --short HEAD)" || echo "no changes"
git -C "$TMP" push -q origin gh-pages
git worktree remove --force "$TMP"
echo "Deployed. https://$L.github.io/$(basename "$(git remote get-url origin)" .git)/"
