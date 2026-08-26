package adapters_test

import (
	"testing"
	"time"

	"warehouse/internal/adapters"
)

// TestRealClockNowReturnsPlausibleTime pins the production clock's contract:
// it returns a non-zero time close to the caller's present instant.
func TestRealClockNowReturnsPlausibleTime(t *testing.T) {
	t.Parallel()

	before := time.Now()
	got := (adapters.RealClock{}).Now()
	after := time.Now()

	if got.IsZero() {
		t.Fatal("RealClock.Now returned the zero instant")
	}
	if got.Before(before.Add(-time.Second)) || got.After(after.Add(time.Second)) {
		t.Fatalf("RealClock.Now = %v, want within [%v, %v]", got, before, after)
	}
}
