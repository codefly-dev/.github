package runtime

import (
	"context"
	"os/exec"

	argoclient "github.com/argoproj/argo-cd/v3/pkg/apiclient"
	fluxclient "github.com/fluxcd/pkg/runtime/client"
	"github.com/go-git/go-git/v5"
	"github.com/google/go-github/v60/github"
)

type Application struct{}
type AppProject struct{}

func Render(ctx context.Context, repositoryURL, repositoryBranch, targetRevision string) error {
	_ = argoclient.ClientOptions{}
	_ = fluxclient.Options{}
	_ = Application{}
	_ = AppProject{}
	_ = repositoryBranch
	if _, err := git.PlainClone("/tmp/repo", false, &git.CloneOptions{URL: repositoryURL}); err != nil {
		return err
	}
	if err := exec.Command("git", "checkout", targetRevision).Run(); err != nil {
		return err
	}
	client := github.NewClient(nil)
	_, _, err := client.PullRequests.Create(ctx, "codefly-dev", "example", nil)
	return err
}
