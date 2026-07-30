#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: verify.sh PLUGIN_GO_TEST_JSON CORE_GO_TEST_JSON" >&2
  exit 2
fi

plugin_log="$1"
core_log="$2"

if ! jq -e '
  select(
    .Action == "pass" and
    ((.Test // "") | endswith("/contract/positive"))
  )
' "$plugin_log" >/dev/null; then
  echo "manifest-conformance: the plugin did not run agenttesting.AssertKustomizeTemplates." >&2
  exit 1
fi

required_core_tests=(
  TestDeployKustomizeEmitsDeterministicManifestBundle
  TestDeployKustomizeRendersRestrictedSecretFreeTreeWithoutClusterAccess
  TestDeployKustomizeRejectsSecretBytesForRestricted
  TestKubernetesPluginContractHasNoDeliverySystemTerms
  TestRestrictedProfileHasNoDeliverySystemDependencies
)

for test_name in "${required_core_tests[@]}"; do
  if ! jq -e --arg test_name "$test_name" '
    select(.Action == "pass" and .Test == $test_name)
  ' "$core_log" >/dev/null; then
    echo "manifest-conformance: Core test $test_name did not pass." >&2
    exit 1
  fi
done

echo "manifest-conformance: verified plugin rendering plus deterministic, canonical, digest-pinned, secret-free Core bundle evidence."
