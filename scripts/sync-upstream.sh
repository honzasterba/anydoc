#!/bin/sh
# Sync this fork with upstream and release the gem for whatever crate version
# that brings in.
#
#   1. merges upstream/main into main
#   2. points the gem at the crate version the merge landed on
#   3. runs the version gate and the Ruby test suite
#   4. pushes main, then tags ruby-v<version> to publish the gems
#
# Usage (from the repository root):
#   sh scripts/sync-upstream.sh              # the whole chain
#   sh scripts/sync-upstream.sh --dry-run    # report only, change nothing
#   sh scripts/sync-upstream.sh --no-tag     # sync and push, release later
#   sh scripts/sync-upstream.sh --skip-tests # skip the local test run
#
# The tag is what publishes: it runs .github/workflows/release-ruby.yml, which
# cross-compiles every platform gem, tests each one, and pushes them to
# RubyGems through trusted publishing.
set -eu

UPSTREAM_URL=https://github.com/firecrawl/anydoc
BRANCH=main

dry_run=0
tag=1
tests=1

for arg in "$@"; do
  case $arg in
    --dry-run) dry_run=1 ;;
    --no-tag) tag=0 ;;
    --skip-tests) tests=0 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "error: unknown option $arg" >&2; exit 1 ;;
  esac
done

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
run() { if [ "$dry_run" -eq 1 ]; then printf '   would run: %s\n' "$*"; else "$@"; fi; }

[ -f Cargo.toml ] && [ -d ruby ] || die "run this from the repository root."

# Read `version = "..."` from a manifest's [package] section.
crate_version() {
  awk '
    /^\[package\]/ { in_package = 1; next }
    /^\[/          { in_package = 0 }
    in_package && $1 == "version" { gsub(/"/, "", $3); print $3; exit }
  ' "$1"
}

gem_version() {
  sed -n 's/^[[:space:]]*VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
    ruby/lib/anydoc/version.rb | head -n 1
}

# A clean tree keeps the merge and the version bump separable, and keeps this
# script from committing whatever else was in progress. Untracked files are
# left out of it: they cannot conflict with the merge.
[ -z "$(git status --porcelain --untracked-files=no)" ] ||
  die "tracked files have uncommitted changes; commit or stash them first."

current_branch=$(git rev-parse --abbrev-ref HEAD)
[ "$current_branch" = "$BRANCH" ] || die "on branch '$current_branch'; switch to $BRANCH first."

if ! git remote get-url upstream > /dev/null 2>&1; then
  say "adding the upstream remote ($UPSTREAM_URL)"
  run git remote add upstream "$UPSTREAM_URL"
fi

say "fetching"
git fetch --quiet upstream
git fetch --quiet origin

incoming=$(git log --oneline "HEAD..upstream/$BRANCH" | wc -l | tr -d ' ')
if [ "$incoming" -gt 0 ]; then
  say "$incoming new upstream commit(s):"
  git log --oneline --no-decorate "HEAD..upstream/$BRANCH" | sed 's/^/    /'
  say "merging upstream/$BRANCH"
  if [ "$dry_run" -eq 0 ]; then
    if ! git merge --no-edit "upstream/$BRANCH"; then
      conflicts=$(git diff --name-only --diff-filter=U | sed 's/^/    /')
      printf 'error: the merge conflicts in:\n%s\n' "$conflicts" >&2
      printf 'fix them, `git commit`, then run this script again.\n' >&2
      exit 1
    fi
  else
    printf '   would run: git merge --no-edit upstream/%s\n' "$BRANCH"
  fi
else
  say "no new upstream commits"
fi

crate=$(crate_version Cargo.toml)
gem=$(gem_version)
[ -n "$crate" ] || die "could not read the crate version from Cargo.toml."
[ -n "$gem" ] || die "could not read VERSION from ruby/lib/anydoc/version.rb."

if [ "$crate" != "$gem" ]; then
  say "pointing the gem at anydoc $crate (was $gem)"
  if [ "$dry_run" -eq 0 ]; then
    tmp=$(mktemp)
    sed "s/^\([[:space:]]*VERSION[[:space:]]*=[[:space:]]*\)\"[^\"]*\"/\1\"$crate\"/" \
      ruby/lib/anydoc/version.rb > "$tmp" && mv "$tmp" ruby/lib/anydoc/version.rb
    tmp=$(mktemp)
    sed "s/^anydoc = \"[^\"]*\"/anydoc = \"$crate\"/" \
      ruby/ext/anydoc/Cargo.toml > "$tmp" && mv "$tmp" ruby/ext/anydoc/Cargo.toml
    git add ruby/lib/anydoc/version.rb ruby/ext/anydoc/Cargo.toml
    git commit --quiet -m "chore(ruby): track anydoc $crate"
  else
    printf '   would bump ruby/lib/anydoc/version.rb and ruby/ext/anydoc/Cargo.toml\n'
  fi
else
  say "the gem already tracks anydoc $crate"
fi

say "checking the version locations agree"
sh scripts/check-versions.sh > /dev/null || die "the version gate failed; see the output above."

if [ "$tests" -eq 1 ]; then
  say "compiling the extension and running the tests"
  if [ "$dry_run" -eq 0 ]; then
    (cd ruby && bundle exec rake) || die "the Ruby test suite failed; nothing was pushed."
  else
    printf '   would run: cd ruby && bundle exec rake\n'
  fi
else
  say "skipping the tests"
fi

if [ -n "$(git log --oneline "origin/$BRANCH..HEAD")" ]; then
  say "pushing $BRANCH"
  run git push origin "$BRANCH"
else
  say "$BRANCH is already up to date on origin"
fi

if [ "$tag" -eq 0 ]; then
  say "done (--no-tag); tag ruby-v$crate when you want to publish"
  exit 0
fi

if git rev-parse -q --verify "refs/tags/ruby-v$crate" > /dev/null ||
   git ls-remote --exit-code --tags origin "ruby-v$crate" > /dev/null 2>&1; then
  say "ruby-v$crate is already tagged; nothing to release"
  exit 0
fi

say "tagging ruby-v$crate"
run git tag "ruby-v$crate"
run git push origin "ruby-v$crate"
say "release-ruby.yml is building and publishing the gems for $crate"
