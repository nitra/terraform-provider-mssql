#!/usr/bin/env bash
# Merges muecahit94/terraform-provider-mssql into this repository.
#
# Upstream code uses the module path github.com/muecahit94/terraform-provider-mssql,
# this repository github.com/nitra/terraform-provider-mssql. A plain merge brings the
# old path in with every new or changed file, so after the merge the path (and the
# provider source in docs, examples and scripts) is renamed again, then the result
# is built and tested.
#
#   scripts/sync-upstream.sh            fetch, merge, rename, build, test
#   scripts/sync-upstream.sh --finish   only the rename, build and test; run it
#                                       after resolving the conflicts of a merge
#
# Keep our side of the conflicts in the files this repository owns: the module
# path, .github/workflows, .goreleaser.yml, CHANGELOG.md, README.md, CONTRIBUTING.md.
# Do not squash the merge request of the result: the merge commit is what makes
# upstream an ancestor, so the next sync only brings what is new.
set -euo pipefail

UPSTREAM_URL=https://github.com/muecahit94/terraform-provider-mssql.git
OLD_MODULE=github.com/muecahit94/terraform-provider-mssql
NEW_MODULE=github.com/nitra/terraform-provider-mssql

cd "$(git rev-parse --show-toplevel)"

rename_and_check() {
  # Go sources and go.mod: the module path.
  { grep -rIl --include='*.go' --include='go.mod' "$OLD_MODULE" . 2>/dev/null || true; } | { grep -v '^./.git/' || true; } |
    while read -r file; do perl -pi -e "s#\Q$OLD_MODULE\E#$NEW_MODULE#g" "$file"; done
  # Provider address and provider source of the docs, examples and scripts.
  # CHANGELOG.md keeps the links to upstream and LICENSE keeps its copyright.
  perl -pi -e 's#registry\.terraform\.io/muecahit94/mssql#registry.opentofu.org/nitra/mssql#g' main.go
  { grep -rIl --exclude=sync-upstream.sh --include='*.md' --include='*.tf' --include='*.sh' 'muecahit94/mssql' README.md CONTRIBUTING.md docs examples scripts 2>/dev/null || true; } |
    while read -r file; do perl -pi -e 's#"nitra/mssql"#"nitra/mssql"#g' "$file"; done

  go mod tidy
  go build ./...
  go vet ./...
  go test ./internal/...
  echo "build and tests pass; review 'git diff' for anything that still names muecahit94:"
  git grep -n 'muecahit94' -- . ':!CHANGELOG.md' ':!LICENSE' ':!scripts/sync-upstream.sh' ':!*.go' || true
}

if [ "${1:-}" = "--finish" ]; then
  rename_and_check
  exit 0
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "the working tree is not clean; commit or stash first" >&2
  exit 1
fi

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"
git fetch upstream main

if [ "$(git rev-list --count HEAD..upstream/main)" -eq 0 ]; then
  echo "already in sync with upstream/main ($(git rev-parse --short upstream/main))"
  exit 0
fi

echo "new upstream commits:"
git log --oneline HEAD..upstream/main

if ! git merge --no-edit upstream/main; then
  echo >&2
  echo "conflicts: resolve them (see the header of this script), 'git add' the files," >&2
  echo "then run 'scripts/sync-upstream.sh --finish' and commit the merge." >&2
  exit 1
fi

rename_and_check
if ! git diff --quiet; then
  git commit -a -m "chore: rename the module path in the code merged from upstream"
fi
echo "merged. Open a pull request and merge it with a merge commit, not a squash."
