#!/usr/bin/env bash
#
# Scan a Codefly plugin working tree for delivery/ownership concepts that must
# never appear in a manifest-only Kubernetes plugin. A conforming plugin is a
# deterministic manifest producer: it must not know about Git, GitHub, pull
# requests, Argo CD / Flux, or repository/revision binding.
#
# Exclusions are path-based only. Release automation and test fixtures are
# allowed to reference Git through EXCLUDE_PATHS; runtime source and generated
# plugin-owned output get no in-code exceptions.
#
# Environment:
#   SCAN_ROOT             directory to scan (default: .)
#   EXTRA_EXCLUDE_PATHS   newline-separated glob patterns to exclude, in
#                         addition to the built-in defaults
#
# Exit status: 0 when clean, 1 when any forbidden concept is found.

set -euo pipefail

SCAN_ROOT="${SCAN_ROOT:-.}"

# Path globs excluded from the scan. `*` spans '/'. Release automation lives
# under .github/ and legitimately drives Git; *_test.go and testdata/ hold
# fixtures that assert rejection of the very concepts we forbid at runtime.
DEFAULT_EXCLUDES='.git
.git/*
*/.git/*
.github/*
*/.github/*
*_test.go
testdata/*
*/testdata/*'

# Forbidden concepts as "label::regex" pairs. Regexes are extended (grep -E)
# and matched case-insensitively. Each targets a delivery/ownership concept
# named in the manifest-only plugin contract.
PATTERNS=(
  'Argo/Flux API group::argoproj\.io'
  'Argo/Flux API group::fluxcd\.io'
  'Argo Application kind::kind:[[:space:]]*Application([[:space:]]|$|")'
  'Argo AppProject kind::kind:[[:space:]]*AppProject'
  'Repository URL binding::repoURL'
  'Target revision binding::targetRevision'
  'Git library (go-git)::go-git'
  'GitHub API client::go-github'
  'GitHub GraphQL client::githubv4|githubql'
  'Pull request operation::PullRequest|pulls\.(Create|Edit|List)'
  'Git process execution::exec\.Command(Context)?\([^)]*"git"'
  'Git SSH remote::git@github\.com'
)

matches_any_exclude() {
  local path="$1" pattern
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    # shellcheck disable=SC2254 # intentional glob match, not literal
    case "$path" in
      $pattern) return 0 ;;
    esac
  done <<EOF
$DEFAULT_EXCLUDES
${EXTRA_EXCLUDE_PATHS:-}
EOF
  return 1
}

cd "$SCAN_ROOT"

# Collect scannable files, sorted for deterministic reporting.
files=()
while IFS= read -r -d '' file; do
  rel="${file#./}"
  matches_any_exclude "$rel" && continue
  files+=("$rel")
done < <(find . -type f -print0 | sort -z)

violations=0
for pair in "${PATTERNS[@]}"; do
  label="${pair%%::*}"
  regex="${pair#*::}"
  [ "${#files[@]}" -eq 0 ] && break
  # grep across the file list; -I skips binaries, -H/-n give file:line context.
  if hits="$(grep -EInH "$regex" "${files[@]}" 2>/dev/null)"; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      echo "FORBIDDEN [$label] $line"
      violations=$((violations + 1))
    done <<<"$hits"
  fi
done

if [ "$violations" -gt 0 ]; then
  echo ""
  echo "manifest-ownership-scan: FAILED — $violations forbidden reference(s) in runtime/generated output."
  echo "A manifest-only plugin must not own Git/GitHub/Argo/repository responsibilities."
  exit 1
fi

echo "manifest-ownership-scan: clean — no forbidden ownership concepts found in ${SCAN_ROOT}."
