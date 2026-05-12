package main

import (
	"fmt"
	"strconv"
	"strings"
)

// validFuelTypes mirrors the four sub-tables ED stores per warehouse:
// jet_fuel / gasoline / diesel / methanol_mixture. Each holds an InitFuel
// percentage 0..100.
var validFuelTypes = map[string]struct{}{
	"jet_fuel":         {},
	"gasoline":         {},
	"diesel":           {},
	"methanol_mixture": {},
}

// splitKVLast splits on the LAST '=' so values like 'F-16C bl.50=100' or
// 'weird=name=42' parse correctly (the value is always the trailing
// numeric tail). Returns key, value, ok.
func splitKVLast(s string) (string, string, bool) {
	i := strings.LastIndex(s, "=")
	if i <= 0 || i == len(s)-1 {
		return "", "", false
	}
	return s[:i], s[i+1:], true
}

// parseFuelOverrides parses ["jet_fuel=80", "gasoline=50"] into a map.
// Each value must be 0..100 inclusive. Unknown fuel types and bad K=V
// syntax both error. Last-wins on duplicate keys.
func parseFuelOverrides(raws []string) (map[string]int, error) {
	out := make(map[string]int, len(raws))
	for _, raw := range raws {
		k, v, ok := splitKVLast(raw)
		if !ok {
			return nil, fmt.Errorf("--fuel %q: expected TYPE=N (e.g. jet_fuel=80)", raw)
		}
		if _, valid := validFuelTypes[k]; !valid {
			return nil, fmt.Errorf("--fuel %q: unknown fuel type %q (must be jet_fuel, gasoline, diesel, or methanol_mixture)", raw, k)
		}
		n, err := strconv.Atoi(v)
		if err != nil {
			return nil, fmt.Errorf("--fuel %q: %w", raw, err)
		}
		if n < 0 || n > 100 {
			return nil, fmt.Errorf("--fuel %q: value %d out of range (0..100)", raw, n)
		}
		out[k] = n
	}
	return out, nil
}

// parseAircraftOverrides parses ["F-16C bl.50=100"] into {name: count}.
// Count must be >= 0. Last-wins on duplicate keys.
func parseAircraftOverrides(raws []string) (map[string]int, error) {
	out := make(map[string]int, len(raws))
	for _, raw := range raws {
		k, v, ok := splitKVLast(raw)
		if !ok || k == "" {
			return nil, fmt.Errorf("--aircraft %q: expected NAME=N (e.g. \"F-16C bl.50=100\")", raw)
		}
		n, err := strconv.Atoi(v)
		if err != nil {
			return nil, fmt.Errorf("--aircraft %q: %w", raw, err)
		}
		if n < 0 {
			return nil, fmt.Errorf("--aircraft %q: count must be >= 0", raw)
		}
		out[k] = n
	}
	return out, nil
}

// WeaponOverride is one --weapon flag value (name + count). Order matters
// for the resolved-weapons list passed to Lua; we keep a slice rather
// than a map so duplicates and order are preserved.
type WeaponOverride struct {
	Name  string
	Count int
}

// parseWeaponOverrides parses ["GBU-12=400", "AIM-120C-7=200"] into
// []WeaponOverride preserving order. Count must be >= 0.
func parseWeaponOverrides(raws []string) ([]WeaponOverride, error) {
	out := make([]WeaponOverride, 0, len(raws))
	for _, raw := range raws {
		k, v, ok := splitKVLast(raw)
		if !ok || k == "" {
			return nil, fmt.Errorf("--weapon %q: expected NAME=N (e.g. \"GBU-12=400\")", raw)
		}
		n, err := strconv.Atoi(v)
		if err != nil {
			return nil, fmt.Errorf("--weapon %q: %w", raw, err)
		}
		if n < 0 {
			return nil, fmt.Errorf("--weapon %q: count must be >= 0", raw)
		}
		out = append(out, WeaponOverride{Name: k, Count: n})
	}
	return out, nil
}
