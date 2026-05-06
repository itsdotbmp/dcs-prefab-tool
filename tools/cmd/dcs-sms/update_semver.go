package main

import (
	"strconv"
	"strings"
)

// compareVersion returns -1 if a < b, 0 if a == b, +1 if a > b.
//
// Format: MAJOR.MINOR.PATCH with an optional `-prerelease` suffix.
// Anything after the first '-' is the prerelease.
//
// Ordering:
//   - Numeric triple compared numerically (so 0.10.0 > 0.9.0).
//   - A version without prerelease is greater than the same numerics
//     with a prerelease ("0.1.0" > "0.1.0-dev").
//   - Among prereleases, lexical comparison ("0.1.0-alpha" < "0.1.0-beta").
//
// Optional leading "v" is stripped before parsing.
// Unparseable input returns 0 (treat as equal — fail open).
func compareVersion(a, b string) int {
	a = strings.TrimPrefix(a, "v")
	b = strings.TrimPrefix(b, "v")

	aBase, aPre := splitPrerelease(a)
	bBase, bPre := splitPrerelease(b)

	aParts, ok := parseTriple(aBase)
	if !ok {
		return 0
	}
	bParts, ok := parseTriple(bBase)
	if !ok {
		return 0
	}

	for i := 0; i < 3; i++ {
		if aParts[i] < bParts[i] {
			return -1
		}
		if aParts[i] > bParts[i] {
			return +1
		}
	}

	// Numerics equal — compare prerelease.
	// No-prerelease is greater than has-prerelease.
	switch {
	case aPre == "" && bPre != "":
		return +1
	case aPre != "" && bPre == "":
		return -1
	case aPre < bPre:
		return -1
	case aPre > bPre:
		return +1
	default:
		return 0
	}
}

func splitPrerelease(v string) (base, pre string) {
	i := strings.Index(v, "-")
	if i < 0 {
		return v, ""
	}
	return v[:i], v[i+1:]
}

func parseTriple(s string) ([3]int, bool) {
	parts := strings.SplitN(s, ".", 3)
	if len(parts) != 3 {
		return [3]int{}, false
	}
	var out [3]int
	for i, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil || n < 0 {
			return [3]int{}, false
		}
		out[i] = n
	}
	return out, true
}
