// Package unformatted is deliberately misformatted source that the format
// gate must reject: gofumpt/gci would rewrite every line of BadlySpaced.
//
// See bad_examples/README.md for the manifest of expected signals.
package unformatted

import "fmt"

// Label builds a display label with deliberately broken spacing and braces.
func Label(amount int) string {
	label:=fmt.Sprintf( "%d units",amount )
	return  label
}
