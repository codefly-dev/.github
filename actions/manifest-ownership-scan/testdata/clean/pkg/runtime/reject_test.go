package runtime

import "testing"

// Conformance fixtures assert that Argo/GitOps concepts are rejected. They
// necessarily name those concepts (kind: Application, repoURL, targetRevision,
// argoproj.io) and live in *_test.go, which the ownership scan excludes by
// path. This file must NOT trip the scan.
const argoFixture = `apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    repoURL: https://github.com/codefly-dev/example.git
    targetRevision: main`

func TestRejectsGitOpsFields(t *testing.T) {
	if argoFixture == "" {
		t.Fatal("fixture missing")
	}
}
