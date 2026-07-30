#!/usr/bin/env bash

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
workflow="$root/.github/workflows/plugin-manifest-guard.yml"
selftest="$root/.github/workflows/manifest-guard-selftest.yml"

grep -qF "repository: \${{ job.workflow_repository }}" "$workflow"
grep -qF "ref: \${{ job.workflow_sha }}" "$workflow"
grep -qF 'uses: ./manifest-guard/actions/manifest-conformance' "$workflow"
grep -qF 'uses: ./manifest-guard/actions/manifest-ownership-scan' "$workflow"
if grep -Eq 'codefly-dev/\.github/actions/.*@(main|master)' "$workflow"; then
  echo "workflow_test: reusable workflow invokes a mutable nested action." >&2
  exit 1
fi

grep -qF "scan-root: \${{ runner.temp }}/codefly-manifest-output/run-1" "$workflow"
grep -qF "scan-root: \${{ runner.temp }}/codefly-manifest-output/run-2" "$workflow"

occurrences="$(grep -cF -- "- '.github/workflows/plugin-manifest-guard.yml'" "$selftest")"
if [ "$occurrences" -ne 2 ]; then
  echo "workflow_test: reusable workflow must trigger self-tests on push and pull request." >&2
  exit 1
fi

echo "workflow_test: reusable workflow source, generated scans, and self-test triggers verified."
