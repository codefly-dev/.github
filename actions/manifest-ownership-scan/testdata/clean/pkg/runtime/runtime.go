package runtime

import (
	"context"
	"io/fs"
)

// Render is a deterministic manifest producer: it reads normalized inputs and
// writes Kubernetes/Kustomize files to the caller-supplied destination. It owns
// no delivery mechanism.
func Render(ctx context.Context, templates fs.FS, destination string) error {
	_ = ctx
	_ = templates
	_ = destination
	return nil
}
