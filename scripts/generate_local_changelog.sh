#!/usr/bin/env bash
# Generates CHANGELOG.md locally and copies it into the iOS app's bundled
# resource location so the in-app Settings > Changelog screen shows it on
# the next build.
#
# Uses `conventional-changelog-cli` (the same engine semantic-release uses
# under the hood) to render release notes purely from local git history.
# No remote calls, no GitHub auth, no tags created, no commits made.
#
# Usage:
#   npm run changelog:local
#
# Behavior:
#   - Generates a fresh CHANGELOG.md at the repo root containing all
#     conventional-commit history across every existing tag.
#   - Copies it into src/Onpa/Resources/CHANGELOG.md so the next iOS build
#     embeds the real changelog.
#   - Removes the temporary root-level CHANGELOG.md afterward so the working
#     tree only differs in the bundled resource (which you can revert with
#     `git checkout src/Onpa/Resources/CHANGELOG.md`).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROOT_CHANGELOG="$ROOT_DIR/CHANGELOG.md"
BUNDLED_CHANGELOG="$ROOT_DIR/src/Onpa/Resources/CHANGELOG.md"
HAD_ROOT_CHANGELOG=0
ROOT_CHANGELOG_BACKUP="$(mktemp -u -t onpa-changelog-backup.XXXXXX)"

cleanup() {
  if [[ "$HAD_ROOT_CHANGELOG" == "1" ]]; then
    if [[ -f "$ROOT_CHANGELOG_BACKUP" ]]; then
      mv "$ROOT_CHANGELOG_BACKUP" "$ROOT_CHANGELOG"
    fi
  else
    rm -f "$ROOT_CHANGELOG"
  fi
  rm -f "$ROOT_CHANGELOG_BACKUP"
}
trap cleanup EXIT

# Preserve any existing root CHANGELOG.md so the working tree stays clean.
if [[ -f "$ROOT_CHANGELOG" ]]; then
  HAD_ROOT_CHANGELOG=1
  cp "$ROOT_CHANGELOG" "$ROOT_CHANGELOG_BACKUP"
fi

CHANGELOG_TITLE='# Changelog

All notable changes to Onpa are documented here. This file is generated automatically by [semantic-release](https://github.com/semantic-release/semantic-release) on each release.
'

echo "Generating local changelog from conventional commits..."

# Start with the title header so the in-app parser has a stable preamble.
printf '%s\n' "$CHANGELOG_TITLE" >"$ROOT_CHANGELOG"

# `-r 0` releases all available tags into the changelog (full history).
# `-p angular` matches the preset semantic-release/commit-analyzer uses by
# default, so the output looks identical to a real release.
npx --yes -p conventional-changelog-cli@^5 conventional-changelog \
  -p angular \
  -r 0 \
  >>"$ROOT_CHANGELOG"

# conventional-changelog uses package.json's `version` for the "next release"
# heading, which in this repo is the placeholder `0.0.0-development`. Rename
# that section to "Unreleased" so the in-app changelog reads naturally.
if grep -q '0.0.0-development' "$ROOT_CHANGELOG"; then
  python3 - "$ROOT_CHANGELOG" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    text = fh.read()

# Match "# [0.0.0-development](compare-url) (date)" or bare "# 0.0.0-development (date)".
text = re.sub(
    r"^# \[?0\.0\.0-development\]?(?:\([^)]*\))? \(([^)]+)\)",
    r"# Unreleased (\1)",
    text,
    flags=re.MULTILINE,
)

with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PY
fi

if [[ ! -s "$ROOT_CHANGELOG" ]]; then
  echo "conventional-changelog produced no output." >&2
  exit 65
fi

echo "Copying generated CHANGELOG.md into $BUNDLED_CHANGELOG..."
cp "$ROOT_CHANGELOG" "$BUNDLED_CHANGELOG"

cat <<'EOF'

Done. Rebuild the iOS app to see the new changelog in Settings > Changelog.

Note: src/Onpa/Resources/CHANGELOG.md has been overwritten with the preview.
      Restore the dev placeholder when you're finished:

        git checkout src/Onpa/Resources/CHANGELOG.md

EOF
