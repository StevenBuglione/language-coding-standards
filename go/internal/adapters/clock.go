package adapters

import (
	"time"

	"warehouse/internal/application"
)

// RealClock is the production application.Clock: it reads the wall clock.
//
// This file is the ONLY place in production code allowed to call time.Now;
// forbidigo bans the call everywhere else, forcing time to enter as values or
// through this injected port.
type RealClock struct{}

// Now returns the current local wall-clock instant.
func (RealClock) Now() time.Time {
	return time.Now()
}

// compile-time proof that the adapter satisfies its port.
var _ application.Clock = RealClock{}
