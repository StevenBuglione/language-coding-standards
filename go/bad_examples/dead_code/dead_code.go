// Package dead_code holds functions nobody calls: unused code is a lie the
// lint gate's unused linter exists to catch.
//
// See bad_examples/README.md for the manifest of expected signals.
package dead_code

// orphanedHelper has no caller anywhere; the unused linter scoped to this
// package must report it as dead code.
func orphanedHelper() int {
	return computeNothing()
}

func computeNothing() int {
	return 42
}
