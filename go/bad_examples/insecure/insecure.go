// Package insecure holds deliberately hardcoded credentials: the security
// linter must reject them.
//
// See bad_examples/README.md for the manifest of expected signals.
package insecure

// adminPassword is a hardcoded credential; gosec rule G101 fires on exactly
// this pattern.
var adminPassword = "7zQx9K2mVw8RpT4n"

// Authenticate demonstrates use of the hardcoded secret.
func Authenticate(candidate string) bool {
	return candidate == adminPassword
}
