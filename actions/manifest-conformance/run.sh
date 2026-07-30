#!/usr/bin/env bash

set -euo pipefail

action_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
working_directory="${MANIFEST_GUARD_WORKING_DIRECTORY:-.}"
output_root="${MANIFEST_GUARD_OUTPUT_ROOT:?MANIFEST_GUARD_OUTPUT_ROOT is required}"
environment="manifest-guard"
namespace="codefly-manifest-guard"

case "$output_root" in
  "" | /)
    echo "manifest-conformance: unsafe output root '$output_root'." >&2
    exit 2
    ;;
esac

mkdir -p "$output_root"
output_root="$(cd "$output_root" && pwd)"
run_one="$output_root/run-1"
run_two="$output_root/run-2"
rm -rf "$run_one" "$run_two"

cd "$working_directory"

full_log="$output_root/plugin-tests.json"
go test -json ./... |
  tee "$full_log" |
  jq -jr 'select(.Action == "output") | .Output'

if ! GOWORK=off go list -mod=readonly -m github.com/codefly-dev/core >/dev/null 2>&1; then
  echo "manifest-conformance: plugin go.mod must require github.com/codefly-dev/core v0.2.59 or newer." >&2
  exit 1
fi

verifier_mod="$(mktemp .codefly-manifest-guard-XXXXXX.mod)"
verifier_sum="${verifier_mod%.mod}.sum"
cp go.mod "$verifier_mod"
if [ -f go.sum ]; then
  cp go.sum "$verifier_sum"
fi
cleanup_verifier_module() {
  rm -f "$verifier_mod" "$verifier_sum"
}
trap cleanup_verifier_module EXIT

core_log="$output_root/core-tests.json"
GOWORK=off go test -mod=mod -modfile="$verifier_mod" -json github.com/codefly-dev/core/agents/services \
  -run '^(TestDeployKustomizeEmitsDeterministicManifestBundle|TestDeployKustomizeRendersRestrictedSecretFreeTreeWithoutClusterAccess|TestDeployKustomizeRejectsSecretBytesForRestricted|TestKubernetesPluginContractHasNoDeliverySystemTerms|TestRestrictedProfileHasNoDeliverySystemDependencies)$' \
  -count=1 |
  tee "$core_log" |
  jq -jr 'select(.Action == "output") | .Output'

run_render() {
  local destination="$1"
  local render_log="$2"

  CODEFLY_MANIFEST_DESTINATION="$destination" \
  CODEFLY_MANIFEST_ENVIRONMENT="$environment" \
  CODEFLY_MANIFEST_NAMESPACE="$namespace" \
  CODEFLY_MANIFEST_PROFILE="KUBERNETES_OUTPUT_PROFILE_RESTRICTED_PORTABLE_V1" \
    go test -json ./... -run '^TestManifestGuardRender$' -count=1 |
    tee "$render_log" |
    jq -jr 'select(.Action == "output") | .Output'
}

render_one_log="$output_root/render-1.json"
render_two_log="$output_root/render-2.json"
run_render "$run_one" "$render_one_log"
run_render "$run_two" "$render_two_log"
"$action_path/verify.sh" "$render_one_log" "$render_two_log" "$core_log"
for destination in "$run_one" "$run_two"; do
  if [ ! -d "$destination" ]; then
    echo "manifest-conformance: TestManifestGuardRender did not create $destination." >&2
    exit 1
  fi
done

GOWORK=off go run -mod=mod -modfile="$verifier_mod" "$action_path/cmd/verify/main.go" \
  -environment "$environment" \
  -namespace "$namespace" \
  "$run_one" \
  "$run_two"
