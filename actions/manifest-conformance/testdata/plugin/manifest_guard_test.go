package plugin

import (
	"os"
	"path/filepath"
	"testing"

	builderv0 "github.com/codefly-dev/core/generated/go/codefly/services/builder/v0"
)

func TestManifestGuardRender(t *testing.T) {
	destination := os.Getenv("CODEFLY_MANIFEST_DESTINATION")
	if destination == "" {
		t.Skip("run by the manifest guard")
	}
	profile := builderv0.KubernetesOutputProfile_KUBERNETES_OUTPUT_PROFILE_RESTRICTED_PORTABLE_V1
	if got, want := os.Getenv("CODEFLY_MANIFEST_PROFILE"), profile.String(); got != want {
		t.Fatalf("profile = %q, want %q", got, want)
	}
	environment := os.Getenv("CODEFLY_MANIFEST_ENVIRONMENT")
	namespace := os.Getenv("CODEFLY_MANIFEST_NAMESPACE")
	value := "stable"
	if os.Getenv("CODEFLY_MANIFEST_TEST_NONDETERMINISTIC") != "" &&
		filepath.Base(destination) == "run-2" {
		value = "changed"
	}

	files := map[string]string{
		"base/configmap.yaml": `apiVersion: v1
kind: ConfigMap
metadata:
  name: manifest-guard
  namespace: ` + namespace + `
data:
  value: ` + value + `
`,
		"base/kustomization.yaml": `apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - configmap.yaml
`,
		filepath.Join("overlays", environment, "kustomization.yaml"): `apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
`,
	}
	if os.Getenv("CODEFLY_MANIFEST_TEST_FORBIDDEN_OUTPUT") != "" {
		files["base/application.yaml"] = "apiVersion: " + "argoproj" + `.io/v1alpha1
kind: App` + `lication
metadata:
  name: delivery-owner
  namespace: ` + namespace + `
spec:
  source:
    repo` + `URL: https://example.invalid/plugin.git
`
		files["base/kustomization.yaml"] = `apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - configmap.yaml
  - application.yaml
`
	}
	for relative, content := range files {
		path := filepath.Join(destination, relative)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}
