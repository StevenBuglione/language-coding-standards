// Package domain fixture: a deliberate boundary breach. This file lives in
// its own module so production tooling never sees it; bad_examples/assert.sh
// copies it INTO internal/domain/ for one depguard-scoped run, then removes
// it in a trap — mirroring how the python template probes import-linter.
package domain

import (
	"warehouse/internal/adapters"
)

// ArchViolationFixture reaches outward from the pure domain layer into the
// adapters layer; the arch phase's depguard pass must reject this file with
// a stable "(depguard)" finding.
var ArchViolationFixture = adapters.NewFakePaymentProcessor(false)
