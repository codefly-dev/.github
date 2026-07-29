package runtime

import (
	"context"
	"os/exec"

	"github.com/go-git/go-git/v5"
	"github.com/google/go-github/v60/github"
)

// Render smuggles delivery responsibilities into plugin runtime code: it clones
// a repository, shells out to git, and opens a pull request. Every one of these
// is a forbidden ownership concept for a manifest-only plugin.
func Render(ctx context.Context, repoURL, targetRevision string) error {
	if _, err := git.PlainClone("/tmp/repo", false, &git.CloneOptions{URL: repoURL}); err != nil {
		return err
	}
	if err := exec.Command("git", "checkout", targetRevision).Run(); err != nil {
		return err
	}
	client := github.NewClient(nil)
	_, _, err := client.PullRequests.Create(ctx, "codefly-dev", "example", nil)
	return err
}
