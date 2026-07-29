# Manifest-only plugin guard

`plugin-manifest-guard` is a reusable workflow that keeps Git / Argo /
repository responsibilities out of Codefly Kubernetes-output plugins. A
conforming plugin is a **deterministic manifest producer** — it must not know
about Git repositories, branches, revisions, pull requests, GitHub, Argo CD, or
Flux. Delivery and promotion live in the CLI/server promotion driver, not in
plugins.

The guard does two things:

1. **Runs the Core manifest-bundle conformance suite.** The default command,
   `go test ./...`, exercises each plugin's deployment/manifest contract test
   (`agenttesting.AssertKustomizeTemplates`), which verifies deterministic
   output, canonical inventory, exact content digests, and secret-free
   restricted mode through Core.
2. **Scans runtime source and generated plugin-owned output** for forbidden
   ownership concepts: Argo/Flux API groups, `kind: Application` /
   `kind: AppProject`, `repoURL`, `targetRevision`, `go-git`, GitHub clients,
   pull-request operations, `exec.Command("git", …)`, and Git SSH remotes.

Exclusions are **path-based only**. Repository release automation (`.github/`)
and test fixtures (`*_test.go`, `testdata/`) are excluded by default; there are
no in-code runtime exceptions.

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
| `conformance-command` | `go test ./...` | Command that runs the Core manifest-bundle conformance suite. |
| `scan-root` | `.` | Directory scanned for ownership concepts. |
| `exclude-paths` | `""` | Newline-separated glob patterns excluded in addition to the defaults. Release automation and test fixtures only. |

Secret `go-token` (optional) configures private Go module access for the
conformance suite.
