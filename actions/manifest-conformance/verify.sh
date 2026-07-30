#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: verify.sh FIRST_RENDER_GO_TEST_JSON SECOND_RENDER_GO_TEST_JSON CORE_GO_TEST_JSON" >&2
  exit 2
fi

for render_log in "$1" "$2"; do
  pass_count="$(
    jq -s '
      [
        .[] |
        select(
          .Action == "pass" and
          .Test == "TestManifestGuardRender"
        )
      ] |
      length
    ' "$render_log"
  )"

  if [ "$pass_count" -ne 1 ]; then
    echo "manifest-conformance: expected exactly one passing TestManifestGuardRender in $render_log; found ${pass_count}." >&2
    exit 1
  fi
done

core_log="$3"
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

echo "manifest-conformance: verified two explicit plugin renders and the Core manifest-bundle suite."
