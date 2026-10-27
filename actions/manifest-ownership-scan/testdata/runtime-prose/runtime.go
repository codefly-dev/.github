package runtime

// A comment that explains control flow is not ownership. This function takes
// the container branch when it must install nothing, whatever revision of the
// plan reached it, and no repository is bound anywhere in it. The caller names
// the "branch" it took, and the "revision" it saw: quoting an English word
// does not bind one either. The declaration forms stay violations — see the
// runtime-identifiers and token-declaration-forms fixtures.
func installsLinkedPackages(container bool) bool {
	if container {
		// Resolved before the container branch below, at any revision.
		return false
	}
	return true
}

// Select a path; branch selection depends on the input.
// Update the plan; revision history remains available.
// Explain the choice { branch selection depends on the input.
// Explain the choice { revision history remains available.
