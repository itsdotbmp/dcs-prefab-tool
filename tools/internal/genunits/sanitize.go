package genunits

import (
	"sort"
	"strconv"
	"strings"
)

// SanitizeIdentifier converts a DCS type-string into a Lua identifier:
//  1. Replace every non-[a-zA-Z0-9_] character with _.
//  2. Collapse runs of _ to a single _.
//  3. If the result starts with a digit, prefix _.
//
// The result is always a valid Lua identifier (Lua 5.1: [_A-Za-z][_A-Za-z0-9]*).
// Empty input maps to "_".
func SanitizeIdentifier(s string) string {
	if s == "" {
		return "_"
	}
	var b strings.Builder
	prevUnderscore := false
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' {
			b.WriteRune(r)
			prevUnderscore = false
		} else {
			if !prevUnderscore {
				b.WriteRune('_')
				prevUnderscore = true
			}
		}
	}
	out := b.String()
	if out == "" {
		return "_"
	}
	if c := out[0]; c >= '0' && c <= '9' {
		out = "_" + out
	}
	return out
}

// ResolveCollisions takes a sorted slice of DCS type-strings and returns
// a map from each input string to a unique Lua identifier. When two inputs
// sanitize to the same identifier, the later one (in lexical order) gets
// _2, _3, ... appended deterministically.
//
// Caller is responsible for sorting the input slice — the function asserts
// determinism by trusting the caller.
func ResolveCollisions(inputs []string) map[string]string {
	out := make(map[string]string, len(inputs))
	used := make(map[string]int) // sanitized identifier -> count seen so far
	// Defensive sort — the contract is "caller sorts" but it's cheap insurance.
	sorted := append([]string(nil), inputs...)
	sort.Strings(sorted)
	for _, raw := range sorted {
		base := SanitizeIdentifier(raw)
		count := used[base]
		var ident string
		if count == 0 {
			ident = base
		} else {
			ident = base + "_" + strconv.Itoa(count+1)
		}
		used[base] = count + 1
		out[raw] = ident
	}
	return out
}
