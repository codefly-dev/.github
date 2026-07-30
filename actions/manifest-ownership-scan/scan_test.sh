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
    "Git library" \
    "GitHub API client" \
    "Git process execution" \
    "Pull request operation" \
    "Argo/Flux API group" \
    "Argo/Flux client" \
    "Argo Application" \
    "Argo AppProject" \
    "Repository URL binding" \
    "Repository branch binding" \
    "Repository revision binding" \
    "Git command"; do
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

# Fixture exclusions leave runtime violations visible.
if out="$(SCAN_ROOT="$here/testdata/dirty" EXTRA_EXCLUDE_PATHS=$'pkg/runtime/fixture_test.go\ntemplates/fixtures/*' bash "$scan" 2>&1)"; then
  fail "fixture exclusions must not hide runtime violations:"$'\n'"$out"
else
  pass "fixture exclusions leave runtime violations visible"
fi

# Runtime and generated-output exclusions are invalid.
if out="$(SCAN_ROOT="$here/testdata/dirty" EXTRA_EXCLUDE_PATHS=$'pkg/*\ntemplates/*' bash "$scan" 2>&1)"; then
  fail "runtime exclusions should be rejected but passed:"$'\n'"$out"
elif grep -qF "only release automation and test-fixture paths may be excluded" <<<"$out"; then
  pass "runtime exclusions are rejected"
else
  fail "runtime exclusion failed without the expected diagnostic:"$'\n'"$out"
fi

echo ""
if [ "$failures" -gt 0 ]; then
  echo "scan_test: $failures assertion(s) failed."
  exit 1
fi
echo "scan_test: all assertions passed."
