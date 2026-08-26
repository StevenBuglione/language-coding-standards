// Package printing prints straight to stdout from library code: forbidigo
// bans fmt.Print* outside cmd/, so the lint gate must reject this file.
//
// See bad_examples/README.md for the manifest of expected signals.
package printing

import "fmt"

// DebugTotal dumps the order total to stdout mid-pipeline.
func DebugTotal(minorUnits int64) {
	fmt.Printf("order total: %d\n", minorUnits)
}
