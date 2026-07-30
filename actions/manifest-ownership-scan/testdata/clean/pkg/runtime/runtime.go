package runtime

import (
	"context"
	"io/fs"
)

type ApplicationController struct{}

func Render(ctx context.Context, templates fs.FS, destination string) error {
	_ = ctx
	_ = templates
	_ = destination
	return nil
}
