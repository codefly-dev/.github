#!/usr/bin/env bash

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
verify="$here/verify.sh"
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

first_render_log="$fixture_dir/render-1.json"
second_render_log="$fixture_dir/render-2.json"
core_log="$fixture_dir/core.json"
printf '%s\n' \
  '{"Action":"pass","Test":"TestManifestGuardRender"}' \
  >"$first_render_log"
cp "$first_render_log" "$second_render_log"
printf '%s\n' \
  '{"Action":"pass","Test":"TestDeployKustomizeEmitsDeterministicManifestBundle"}' \
  '{"Action":"pass","Test":"TestDeployKustomizeRendersRestrictedSecretFreeTreeWithoutClusterAccess"}' \
  '{"Action":"pass","Test":"TestDeployKustomizeRejectsSecretBytesForRestricted"}' \
  '{"Action":"pass","Test":"TestKubernetesPluginContractHasNoDeliverySystemTerms"}' \
  '{"Action":"pass","Test":"TestRestrictedProfileHasNoDeliverySystemDependencies"}' \
  >"$core_log"

if out="$(bash "$verify" "$first_render_log" "$second_render_log" "$core_log" 2>&1)"; then
  pass "two explicit renders and complete Core evidence pass"
else
  fail "complete conformance evidence should pass:"$'\n'"$out"
fi

printf '%s\n' \
  '{"Action":"pass","Test":"TestDeploymentTemplates/contract/positive"}' \
  >"$first_render_log"
if out="$(bash "$verify" "$first_render_log" "$second_render_log" "$core_log" 2>&1)"; then
  fail "a contract/positive subtest must not satisfy the render interface"
elif grep -qF "expected exactly one passing TestManifestGuardRender in $first_render_log; found 0" <<<"$out"; then
  pass "a contract-only helper cannot impersonate the render interface"
else
  fail "contract-only evidence had the wrong diagnostic:"$'\n'"$out"
fi

printf '%s\n' \
  '{"Action":"pass","Test":"TestManifestGuardRender"}' \
  '{"Action":"pass","Test":"TestManifestGuardRender"}' \
  >"$first_render_log"
if out="$(bash "$verify" "$first_render_log" "$second_render_log" "$core_log" 2>&1)"; then
  fail "multiple render owners should fail"
elif grep -qF "expected exactly one passing TestManifestGuardRender in $first_render_log; found 2" <<<"$out"; then
  pass "the render interface has exactly one owner"
else
  fail "duplicate render evidence had the wrong diagnostic:"$'\n'"$out"
fi

printf '%s\n' \
  '{"Action":"pass","Test":"TestManifestGuardRender"}' \
  >"$first_render_log"
sed '/TestDeployKustomizeEmitsDeterministicManifestBundle/d' "$core_log" >"$fixture_dir/incomplete-core.json"
if out="$(bash "$verify" "$first_render_log" "$second_render_log" "$fixture_dir/incomplete-core.json" 2>&1)"; then
  fail "missing Core evidence should fail"
elif grep -qF "Core test TestDeployKustomizeEmitsDeterministicManifestBundle did not pass" <<<"$out"; then
  pass "missing Core evidence fails"
else
  fail "missing Core evidence had the wrong diagnostic:"$'\n'"$out"
fi

echo ""
if [ "$failures" -gt 0 ]; then
  echo "verify_test: $failures assertion(s) failed."
  exit 1
fi
echo "verify_test: all assertions passed."
