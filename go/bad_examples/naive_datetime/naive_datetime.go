// Package naive_datetime reads the wall clock directly instead of going
// through the injected Clock port; forbidigo bans time.Now outside
// internal/adapters/clock.go, so the lint gate must reject this file.
//
// See bad_examples/README.md for the manifest of expected signals.
package naive_datetime

import "time"

// SnapshotAt hides a nondeterministic wall-clock read behind a pure-looking
// name.
func SnapshotAt() time.Time {
	return time.Now()
}
