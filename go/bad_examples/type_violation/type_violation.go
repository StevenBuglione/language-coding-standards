// Package typeviolation holds deliberately broken code: it fails to compile,
// and that is exactly the expected signal for the types gate.
//
// See bad_examples/README.md for the manifest of expected signals.
package typeviolation

// Broken assigns a string where an int is required; go build must fail on
// this file with a mismatched-types error.
func Broken() int {
	count := "not-a-number"
	return count
}
