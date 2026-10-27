package runtime

type Source struct {
	Branch   string `json:"branch"`
	Revision string `json:"revision"`
}

func bind(s *Source) {
	Branch = s.Branch
}
