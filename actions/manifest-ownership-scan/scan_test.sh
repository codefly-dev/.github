#!/usr/bin/env bash
#
# Behavioral tests for scan.sh. Run locally or from the self-test workflow.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scan="$here/scan.sh"
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

# A clean manifest-only tree passes, even though it contains a Git-driven
# release workflow under .github/ and a *_test.go fixture full of GitOps terms.
if out="$(SCAN_ROOT="$here/testdata/clean" bash "$scan" 2>&1)"; then
  pass "clean tree passes"
else
  fail "clean tree should pass but failed:"$'\n'"$out"
fi

# A synthetic runtime Git/Argo/GitHub dependency and generated Argo Application
# output must fail the scan.
if out="$(SCAN_ROOT="$here/testdata/dirty" bash "$scan" 2>&1)"; then
  fail "dirty tree should fail but passed:"$'\n'"$out"
else
  pass "dirty tree fails"
  for label in \
    "Git library (go-git)" \
    "GitHub API client" \
    "Git process execution" \
    "Pull request operation" \
    "Argo/Flux API group" \
    "Argo Application kind" \
    "Repository URL binding" \
    "Target revision binding"; do
    if grep -qF "[$label]" <<<"$out"; then
      pass "dirty tree reports: $label"
    else
      fail "dirty tree missed concept: $label"
    fi
  done
fi

# Excluded paths must not be the reason a dirty tree fails: prove the release
# workflow's git@github.com and the fixture's argoproj.io are never reported
# for the clean tree.
out="$(SCAN_ROOT="$here/testdata/clean" bash "$scan" 2>&1 || true)"
if grep -q "FORBIDDEN" <<<"$out"; then
  fail "clean tree reported a violation from an excluded path:"$'\n'"$out"
else
  pass "excluded release automation and test fixtures are not scanned"
fi

# Caller-supplied EXTRA_EXCLUDE_PATHS suppress an otherwise-failing path.
if out="$(SCAN_ROOT="$here/testdata/dirty" EXTRA_EXCLUDE_PATHS=$'pkg/*\ntemplates/*' bash "$scan" 2>&1)"; then
  pass "EXTRA_EXCLUDE_PATHS suppresses matched paths"
else
  fail "EXTRA_EXCLUDE_PATHS should have suppressed all violations:"$'\n'"$out"
fi

echo ""
if [ "$failures" -gt 0 ]; then
  echo "scan_test: $failures assertion(s) failed."
  exit 1
fi
echo "scan_test: all assertions passed."
