#!/usr/bin/env bash

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
verify="$here/verify.sh"
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

plugin_log="$fixture_dir/plugin.json"
core_log="$fixture_dir/core.json"

printf '%s\n' \
  '{"Action":"pass","Test":"TestDeploymentTemplates/contract/positive"}' \
  >"$plugin_log"
printf '%s\n' \
  '{"Action":"pass","Test":"TestDeployKustomizeEmitsDeterministicManifestBundle"}' \
  '{"Action":"pass","Test":"TestDeployKustomizeRendersRestrictedSecretFreeTreeWithoutClusterAccess"}' \
  '{"Action":"pass","Test":"TestDeployKustomizeRejectsSecretBytesForRestricted"}' \
  '{"Action":"pass","Test":"TestKubernetesPluginContractHasNoDeliverySystemTerms"}' \
  '{"Action":"pass","Test":"TestRestrictedProfileHasNoDeliverySystemDependencies"}' \
  >"$core_log"

if out="$(bash "$verify" "$plugin_log" "$core_log" 2>&1)"; then
  pass "complete conformance evidence passes"
else
  fail "complete evidence should pass:"$'\n'"$out"
fi

printf '%s\n' '{"Action":"pass","Package":"example.com/plugin"}' >"$plugin_log"
if out="$(bash "$verify" "$plugin_log" "$core_log" 2>&1)"; then
  fail "missing plugin conformance should fail"
elif grep -qF "did not run agenttesting.AssertKustomizeTemplates" <<<"$out"; then
  pass "missing plugin conformance fails"
else
  fail "missing plugin conformance had the wrong diagnostic:"$'\n'"$out"
fi

printf '%s\n' \
  '{"Action":"pass","Test":"TestDeploymentTemplates/contract/positive"}' \
  >"$plugin_log"
sed '/TestDeployKustomizeEmitsDeterministicManifestBundle/d' "$core_log" >"$fixture_dir/incomplete-core.json"
if out="$(bash "$verify" "$plugin_log" "$fixture_dir/incomplete-core.json" 2>&1)"; then
  fail "missing Core evidence should fail"
elif grep -qF "TestDeployKustomizeEmitsDeterministicManifestBundle did not pass" <<<"$out"; then
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
