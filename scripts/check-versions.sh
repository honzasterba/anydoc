#!/bin/sh
# Verify that the release version agrees across the seven places it is declared:
#   1. Cargo.toml                 [package].version
#   2. python/Cargo.toml          [package].version
#   3. wasm/Cargo.toml            [package].version (wasm-pack stamps it on @firecrawl/anydoc-wasm)
#   4. node/package.json          .version
#   5. node/index.js              generated version guard (contains `!== '<version>'`)
#   6. ruby/lib/anydoc/version.rb Anydoc::VERSION (the gem version)
#   7. ruby/ext/anydoc/Cargo.toml the `anydoc` dependency, which released gems
#                                 resolve from crates.io
#
# Usage (from the repo root):
#   sh scripts/check-versions.sh          # check agreement only
#   sh scripts/check-versions.sh v1.2.3   # also check that the tag matches
#
# On success prints the agreed version on stdout and exits 0.
# On failure prints actionable errors on stderr and exits 1.
set -u

err=0

report() { printf '%s\n' "$*" >&2; }

for f in Cargo.toml python/Cargo.toml wasm/Cargo.toml node/package.json node/index.js \
         ruby/lib/anydoc/version.rb ruby/ext/anydoc/Cargo.toml; do
  if [ ! -f "$f" ]; then
    report "error: $f not found - run this script from the repository root."
    exit 1
  fi
done

# Read `version = "..."` only from the [package] section, not [dependencies] etc.
toml_version() {
  awk '
    /^\[package\]/ { in_package = 1; next }
    /^\[/          { in_package = 0 }
    in_package && $1 == "version" { gsub(/"/, "", $3); print $3; exit }
  ' "$1"
}

cargo_version=$(toml_version Cargo.toml)
python_version=$(toml_version python/Cargo.toml)
wasm_version=$(toml_version wasm/Cargo.toml)

# npm keeps top-level "version" as the first version key in package.json.
package_json_version=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' node/package.json | head -n 1)

# The generated Node loader embeds the version it was generated for in a guard
# containing the literal substring `!== '<version>'`.
guard_version=$(grep -o "!== '[^']*'" node/index.js | head -n 1 | sed "s/^!== '//; s/'\$//")

gem_version=$(sed -n 's/^[[:space:]]*VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' ruby/lib/anydoc/version.rb | head -n 1)

# The extension crate's `anydoc = "<version>"` dependency, in [dependencies].
gem_crate_version=$(awk '
  /^\[dependencies\]/ { in_deps = 1; next }
  /^\[/               { in_deps = 0 }
  in_deps && $1 == "anydoc" { gsub(/"/, "", $3); print $3; exit }
' ruby/ext/anydoc/Cargo.toml)

[ -n "$cargo_version" ]        || { report "error: could not read [package].version from Cargo.toml"; err=1; }
[ -n "$python_version" ]       || { report "error: could not read [package].version from python/Cargo.toml"; err=1; }
[ -n "$wasm_version" ]         || { report "error: could not read [package].version from wasm/Cargo.toml"; err=1; }
[ -n "$package_json_version" ] || { report "error: could not read .version from node/package.json"; err=1; }
[ -n "$guard_version" ]        || { report "error: could not find the version guard (!== '<version>') in node/index.js - regenerate it with 'npm run build' in node/"; err=1; }
[ -n "$gem_version" ]          || { report "error: could not read VERSION from ruby/lib/anydoc/version.rb"; err=1; }
[ -n "$gem_crate_version" ]    || { report "error: could not read the anydoc dependency from ruby/ext/anydoc/Cargo.toml"; err=1; }

[ "$err" -eq 0 ] || exit 1

if [ "$python_version" != "$cargo_version" ] || \
   [ "$wasm_version" != "$cargo_version" ] || \
   [ "$package_json_version" != "$cargo_version" ] || \
   [ "$guard_version" != "$cargo_version" ] || \
   [ "$gem_version" != "$cargo_version" ] || \
   [ "$gem_crate_version" != "$cargo_version" ]; then
  report "error: the release version locations disagree:"
  report "  Cargo.toml [package].version         = $cargo_version"
  report "  python/Cargo.toml [package].version  = $python_version"
  report "  wasm/Cargo.toml [package].version    = $wasm_version"
  report "  node/package.json .version           = $package_json_version"
  report "  node/index.js version guard          = $guard_version"
  report "  ruby/lib/anydoc/version.rb VERSION   = $gem_version"
  report "  ruby/ext/anydoc/Cargo.toml anydoc    = $gem_crate_version"
  report "fix: set all seven to the same version. Bump the three Cargo.toml files,"
  report "     node/package.json, ruby/lib/anydoc/version.rb, and the anydoc"
  report "     dependency in ruby/ext/anydoc/Cargo.toml, then run 'npm run build'"
  report "     in node/ to regenerate node/index.js, and commit the result."
  exit 1
fi

if [ "$#" -ge 1 ] && [ -n "$1" ]; then
  tag=$1
  if [ "$tag" != "v$cargo_version" ]; then
    report "error: tag '$tag' does not match the declared version '$cargo_version' (expected tag 'v$cargo_version')."
    report "fix: either delete the tag and re-tag the commit that declares ${tag#v},"
    report "     or bump all seven version locations to ${tag#v} and tag that commit."
    exit 1
  fi
fi

printf '%s\n' "$cargo_version"
