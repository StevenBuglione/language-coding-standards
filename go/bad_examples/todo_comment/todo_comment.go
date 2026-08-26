// Package todo_comment carries an unfinished-work marker: the lint phase
// bans TODO/FIXME markers in production code via a grep step, and this
// fixture proves the ban still bites (scoped at bad_examples).
//
// See bad_examples/README.md for the manifest of expected signals.
package todo_comment

// RetryPolicy returns a placeholder that is not actually final.
func RetryPolicy() int {
	// TODO: extract the retry count into configuration before launch.
	return 3
}
