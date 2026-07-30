#!/usr/bin/env bash

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
run="$here/run.sh"
scan="$here/../manifest-ownership-scan/scan.sh"
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

if out="$(
  MANIFEST_GUARD_WORKING_DIRECTORY="$here/testdata/plugin" \
  MANIFEST_GUARD_OUTPUT_ROOT="$fixture_dir/good-output" \
    bash "$run" 2>&1
)"; then
  if [ -f "$fixture_dir/good-output/run-1/base/configmap.yaml" ] &&
    [ -f "$fixture_dir/good-output/run-2/base/configmap.yaml" ] &&
    grep -qF "verified 3 plugin-owned files with canonical inventory sha256:462b7eb543cf129836ba3b742aa8e80dc27b25bd1b038abe36e64225fed3843c." <<<"$out"; then
    pass "actual plugin output is persisted and verified twice"
  else
    fail "successful conformance did not persist and report both renders:"$'\n'"$out"
  fi
else
  fail "deterministic restricted plugin should pass:"$'\n'"$out"
fi

if out="$(
  SCAN_ROOT="$fixture_dir/good-output/run-1" bash "$scan" 2>&1 &&
    SCAN_ROOT="$fixture_dir/good-output/run-2" bash "$scan" 2>&1
)"; then
  pass "persisted clean output passes ownership scanning"
else
  fail "persisted clean output should pass ownership scanning:"$'\n'"$out"
fi

if out="$(
  CODEFLY_MANIFEST_TEST_FORBIDDEN_OUTPUT=1 \
  MANIFEST_GUARD_WORKING_DIRECTORY="$here/testdata/plugin" \
  MANIFEST_GUARD_OUTPUT_ROOT="$fixture_dir/forbidden-output" \
    bash "$run" 2>&1
)"; then
  if scan_out="$(
    SCAN_ROOT="$fixture_dir/forbidden-output/run-1" bash "$scan" 2>&1
  )"; then
    fail "forbidden generated output should fail ownership scanning"
  elif grep -qF "[Argo Application]" <<<"$scan_out" &&
    grep -qF "[Repository URL binding]" <<<"$scan_out"; then
    pass "actual generated ownership output fails scanning"
  else
    fail "generated output failed with the wrong diagnostic:"$'\n'"$scan_out"
  fi
else
  fail "Core should accept the generated custom resource before ownership scanning:"$'\n'"$out"
fi

if out="$(
  CODEFLY_MANIFEST_TEST_NONDETERMINISTIC=1 \
  MANIFEST_GUARD_WORKING_DIRECTORY="$here/testdata/plugin" \
  MANIFEST_GUARD_OUTPUT_ROOT="$fixture_dir/nondeterministic-output" \
    bash "$run" 2>&1
)"; then
  fail "nondeterministic plugin output should fail"
elif grep -qF "renders are not deterministic" <<<"$out"; then
  pass "plugin-specific nondeterminism fails"
else
  fail "nondeterministic output had the wrong diagnostic:"$'\n'"$out"
fi

if out="$(
  MANIFEST_GUARD_WORKING_DIRECTORY="$here/testdata/contract-only" \
  MANIFEST_GUARD_OUTPUT_ROOT="$fixture_dir/contract-only-output" \
    bash "$run" 2>&1
)"; then
  fail "contract/positive without the render interface should fail"
elif grep -qF "expected exactly one passing TestManifestGuardRender in " <<<"$out" &&
  grep -qF "; found 0" <<<"$out"; then
  pass "contract-only plugin cannot satisfy conformance"
else
  fail "contract-only plugin had the wrong diagnostic:"$'\n'"$out"
fi

echo ""
if [ "$failures" -gt 0 ]; then
  echo "run_test: $failures assertion(s) failed."
  exit 1
fi
echo "run_test: all assertions passed."
