package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"github.com/codefly-dev/core/agents/services"
	builderv0 "github.com/codefly-dev/core/generated/go/codefly/services/builder/v0"
)

type manifestFile struct {
	path   string
	digest string
}

func main() {
	environment := flag.String("environment", "", "Kustomize overlay environment")
	namespace := flag.String("namespace", "", "expected Kubernetes namespace")
	flag.Parse()

	if *environment == "" || *namespace == "" || flag.NArg() != 2 {
		fmt.Fprintln(os.Stderr, "usage: verify -environment NAME -namespace NAME FIRST_RENDER SECOND_RENDER")
		os.Exit(2)
	}

	first, err := verifyRender(flag.Arg(0), *environment, *namespace)
	if err != nil {
		fmt.Fprintf(os.Stderr, "manifest-conformance: first render: %v\n", err)
		os.Exit(1)
	}
	second, err := verifyRender(flag.Arg(1), *environment, *namespace)
	if err != nil {
		fmt.Fprintf(os.Stderr, "manifest-conformance: second render: %v\n", err)
		os.Exit(1)
	}
	if err := compareInventories(first, second); err != nil {
		fmt.Fprintf(os.Stderr, "manifest-conformance: renders are not deterministic: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf(
		"manifest-conformance: verified %d plugin-owned files with canonical inventory %s.\n",
		len(first),
		aggregateDigest(first),
	)
}

func verifyRender(destination, environment, namespace string) ([]manifestFile, error) {
	inventory, err := inventoryFiles(destination)
	if err != nil {
		return nil, err
	}
	if len(inventory) == 0 {
		return nil, errors.New("rendered tree is empty")
	}

	profile := builderv0.KubernetesOutputProfile_KUBERNETES_OUTPUT_PROFILE_RESTRICTED_PORTABLE_V1
	validation := services.ValidateKubernetesManifestTree(
		context.Background(),
		destination,
		environment,
		namespace,
		profile,
		false,
		"",
		"",
	)
	if validation.GetStaticValidation() != builderv0.KubernetesManifestValidation_STATUS_PASSED {
		return nil, fmt.Errorf("restricted Core validation failed: %v", validation.GetViolations())
	}
	if !validation.GetRestricted() {
		return nil, errors.New("Core validation did not mark restricted output as restricted")
	}
	if len(validation.GetViolations()) != 0 {
		return nil, fmt.Errorf("Core validation returned violations: %v", validation.GetViolations())
	}

	bundle, err := services.BuildKubernetesManifestBundle(
		destination,
		environment,
		profile,
		validation,
		nil,
	)
	if err != nil {
		return nil, fmt.Errorf("build Core manifest bundle: %w", err)
	}
	if bundle.GetContractVersion() != services.KubernetesManifestContractVersion {
		return nil, fmt.Errorf("unexpected contract version %q", bundle.GetContractVersion())
	}
	if bundle.GetProfile() != profile {
		return nil, fmt.Errorf("unexpected output profile %s", bundle.GetProfile())
	}
	if len(bundle.GetEntryPoints()) != 1 ||
		bundle.GetEntryPoints()[0] != filepath.ToSlash(filepath.Join("overlays", environment)) {
		return nil, fmt.Errorf("unexpected entry points %v", bundle.GetEntryPoints())
	}
	if len(bundle.GetSecretReferences()) != 0 {
		return nil, errors.New("restricted bundle contains secret references")
	}
	if err := compareBundleInventory(inventory, bundle.GetFiles()); err != nil {
		return nil, err
	}
	if want := aggregateDigest(inventory); bundle.GetDigest() != want {
		return nil, fmt.Errorf("bundle digest %q does not match exact inventory digest %q", bundle.GetDigest(), want)
	}

	return inventory, nil
}

func inventoryFiles(root string) ([]manifestFile, error) {
	var files []manifestFile
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			return nil
		}
		content, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		sum := sha256.Sum256(content)
		files = append(files, manifestFile{
			path:   filepath.ToSlash(relative),
			digest: "sha256:" + hex.EncodeToString(sum[:]),
		})
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("inventory rendered tree: %w", err)
	}
	sort.Slice(files, func(i, j int) bool {
		return files[i].path < files[j].path
	})
	return files, nil
}

func compareBundleInventory(want []manifestFile, got []*builderv0.KubernetesManifestFile) error {
	if len(want) != len(got) {
		return fmt.Errorf("Core inventory contains %d files; exact inventory contains %d", len(got), len(want))
	}
	for index := range want {
		if got[index].GetPath() != want[index].path || got[index].GetDigest() != want[index].digest {
			return fmt.Errorf(
				"Core inventory entry %d is %q %q; exact entry is %q %q",
				index,
				got[index].GetPath(),
				got[index].GetDigest(),
				want[index].path,
				want[index].digest,
			)
		}
	}
	return nil
}

func compareInventories(first, second []manifestFile) error {
	if len(first) != len(second) {
		return fmt.Errorf("file count changed from %d to %d", len(first), len(second))
	}
	for index := range first {
		if first[index] != second[index] {
			return fmt.Errorf(
				"entry %d changed from %q %q to %q %q",
				index,
				first[index].path,
				first[index].digest,
				second[index].path,
				second[index].digest,
			)
		}
	}
	if firstDigest, secondDigest := aggregateDigest(first), aggregateDigest(second); firstDigest != secondDigest {
		return fmt.Errorf("aggregate digest changed from %s to %s", firstDigest, secondDigest)
	}
	return nil
}

func aggregateDigest(files []manifestFile) string {
	hasher := sha256.New()
	for _, file := range files {
		fmt.Fprintf(hasher, "%s\x00%s\n", file.path, file.digest)
	}
	return "sha256:" + hex.EncodeToString(hasher.Sum(nil))
}
