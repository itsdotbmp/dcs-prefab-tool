package genunits

import "strings"

// originLabels maps the verbatim _origin field to the user-facing comment
// label per spec decision D7. Entries not in this table either map to the
// empty string (no comment, no origin lookup) — handled in OriginLabel by
// the AI-mod heuristic.
var originLabels = map[string]string{
	"ColdWarAssetsPack": "Cold War Asset Pack",
	"WWII Armour and Technics":                                         "WWII Assets",
	"World War II AI Units by Eagle Dynamics":                          "WWII Assets",
	"World War II PTO Units by Magnitude 3 LLC":                        "WWII Assets",
	"M3 WWII PTO units":                                                "WWII Assets",
	"China Asset Pack by Deka Ironwork Simulations and Eagle Dynamics": "China Asset Pack",
	"USS_Nimitz":              "Supercarrier",
	"Currenthill Assets Pack": "Currenthill Assets",
	"HeavyMetalCore":          "Heavy Metal",
	"Massun92-Assetpack":      "Massun92 Assets",
	"RailwayObjectsPack":      "Railway Objects",
	"South_Atlantic_Assets":   "South Atlantic Assets",
	"TechWeaponPack":          "Tech Weapon Pack",
	"C-130-Assets":            "C-130 Assets",
	"C-130J AI":               "C-130 Assets",
	"Mirage F1 Assets by Aerges": "Mirage F1 Assets",
	"Animals":                "Animals",
	"NS430":                  "NS430",
	"WWII Units":             "WWII Assets",
	"TAVKR 1143 High Detail": "TAVKR 1143",
}

// OriginLabel returns the user-facing comment label for a datamine _origin
// field. Returns empty string for:
//   - Empty input (base-game entry).
//   - Per-aircraft AI mods (D7 says these are treated as base-equivalent).
//   - Anything else not explicitly mapped above.
//
// We detect "per-aircraft AI mod" heuristically: any origin string that
// contains " AI " (with surrounding spaces) or ends with " AI" but is not
// otherwise in the table. This catches "F-14B AI by Heatblur Simulations",
// "Mi-24P AI by Eagle Dynamics", "F-16C bl.50 AI", etc.
func OriginLabel(raw string) string {
	if raw == "" {
		return ""
	}
	if v, ok := originLabels[raw]; ok {
		return v
	}
	// Heuristic: per-aircraft AI mod. These ship with a flyable module
	// most users own; treat them as base-equivalent.
	if strings.Contains(raw, " AI ") || strings.HasSuffix(raw, " AI") {
		return ""
	}
	// Unknown origin — also treat as no-comment to keep the catalog tidy.
	// If a future asset pack appears that we want surfaced, add it to the
	// originLabels table explicitly.
	return ""
}
