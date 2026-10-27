package runtime

type Source struct {
	Branch   string `json:"branch"`
	Revision string `json:"revision"`
}

// Every spelling below BINDS a repository branch or revision. A guard that
// catches only a bare identifier at line start misses all but the last, which
// is the one nobody writes.
func bind(cfg *Config, s *Source) {
	cfg.Branch = "main"
	cfg.Revision = "HEAD"
	cfg.SetBranch(s.Branch)
	_ = Source{Branch: "main", Revision: "HEAD"}
	Branch = s.Branch
}
