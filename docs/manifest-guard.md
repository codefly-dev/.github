# Manifest-only plugin guard

`plugin-manifest-guard` is a reusable workflow that keeps Git / Argo /
repository responsibilities out of Codefly Kubernetes-output plugins. A
conforming plugin is a **deterministic manifest producer** — it must not know
about Git repositories, branches, revisions, pull requests, GitHub, Argo CD, or
Flux. Delivery and promotion live in the CLI/server promotion driver, not in
plugins.

The guard does two things:

1. **Runs and verifies the Core manifest-bundle conformance suite.** It runs
   `go test ./...`, invokes the plugin's explicit manifest render twice, and
   validates both persisted trees with Core from the plugin's `go.mod`. The
   check compares the plugin's canonical file inventories and exact content
   digests, validates the transport-neutral contract, and requires secret-free
   restricted mode. Plugins must use Core `v0.2.59` or newer.
2. **Scans runtime source and generated plugin-owned output** for forbidden
   ownership concepts: Git operations and remotes, repository URL/branch/
   revision bindings, pull requests, GitHub clients, Argo/Flux clients and API
   groups, `Application`, `AppProject`, `repoURL`, and `targetRevision`.

Exclusions are **path-based only**. Repository automation (`.github/`,
`.coderabbit.yaml`, and conventional publish/release script directories) and
test fixtures (`*_test.*`, `testdata/`, `fixtures/`, and conventional test
paths) are excluded by default. Additional exclusions are accepted only for
those same automation and fixture path shapes; runtime paths are rejected.

## Adopt it (Kubernetes-output plugin)

Add `.github/workflows/manifest-guard.yml` to the plugin repo:

```yaml
name: manifest-guard
on:
  pull_request:
  push:
    branches: [ main ]
jobs:
  manifest-guard:
    uses: codefly-dev/.github/.github/workflows/plugin-manifest-guard.yml@main
```

Then mark **`manifest-guard / guard`** as a required status check on the
default branch. Every official Kubernetes-output plugin uses this identical
snippet.

The plugin must own exactly one Go test named `TestManifestGuardRender`. It
must render through the plugin's production manifest path into
`CODEFLY_MANIFEST_DESTINATION`, using the supplied
`CODEFLY_MANIFEST_ENVIRONMENT`, `CODEFLY_MANIFEST_NAMESPACE`, and
`CODEFLY_MANIFEST_PROFILE`. When `CODEFLY_MANIFEST_DESTINATION` is unset, the
test should skip so ordinary `go test ./...` runs remain usable. The guard sets
the profile to
`KUBERNETES_OUTPUT_PROFILE_RESTRICTED_PORTABLE_V1` and invokes the test twice;
the two output trees must be byte-for-byte deterministic.

If the conformance suite pulls private modules (e.g. `codefly-dev/core`), pass a
token:

```yaml
    uses: codefly-dev/.github/.github/workflows/plugin-manifest-guard.yml@main
    secrets:
      go-token: ${{ secrets.CODEFLY_GO_TOKEN }}
```

## Opt out (non-Kubernetes plugin)

Plugins that do not emit Kubernetes manifests explicitly report the capability
as unsupported and pass:

```yaml
jobs:
  manifest-guard:
    uses: codefly-dev/.github/.github/workflows/plugin-manifest-guard.yml@main
    with:
      kubernetes-output: false
```

The required check name (`manifest-guard / guard`) stays identical, so the same
branch-protection rule applies to every plugin repository.

## Inputs

| Input | Default | Purpose |
| --- | --- | --- |
| `kubernetes-output` | `true` | Set `false` to opt out; reports manifest output as unsupported and passes. |
| `go-version-file` | `go.mod` | File the Go version is read from. |
| `exclude-paths` | `""` | Newline-separated release-automation or test-fixture paths excluded in addition to the defaults. Other path shapes fail the check. |

Secret `go-token` (optional) configures private Go module access for the
conformance suite.
