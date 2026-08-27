package domain_test

import (
	"testing"

	"warehouse/internal/domain"
)

func TestDomainErrorMessages(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		err  error
		want string
	}{
		{
			name: "invalid order",
			err:  domain.InvalidOrder{Reason: "bad line"},
			want: "invalid order: bad line",
		},
		{
			name: "payment declined",
			err:  domain.PaymentDeclined{Reason: "no funds"},
			want: "payment declined: no funds",
		},
		{
			name: "persistence conflict",
			err:  domain.PersistenceConflict{Reason: "stale version"},
			want: "persistence conflict: stale version",
		},
		{
			name: "compensation failure",
			err:  domain.CompensationFailure{Stage: "refund", Detail: "gateway down"},
			want: "compensation failed at refund: gateway down",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := tt.err.Error(); got != tt.want {
				t.Fatalf("Error() = %q, want %q", got, tt.want)
			}
		})
	}
}
