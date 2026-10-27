package runtime

func variables() {
	var Branch = "main"
	var Revision = "HEAD"
	_, _ = Branch, Revision
}
func constants() {
	const Branch = "main"
	const Revision = "HEAD"
	_, _ = Branch, Revision
}
type Inline struct { Branch string; Revision string }
