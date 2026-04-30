package genunits

import "testing"

func TestOriginLabel(t *testing.T) {
	cases := []struct {
		raw  string
		want string
	}{
		// Asset packs that get a friendly comment label
		{"ColdWarAssetsPack", "Cold War Asset Pack"},
		{"WWII Armour and Technics", "WWII Assets"},
		{"World War II AI Units by Eagle Dynamics", "WWII Assets"},
		{"World War II PTO Units by Magnitude 3 LLC", "WWII Assets"},
		{"M3 WWII PTO units", "WWII Assets"},
		{"China Asset Pack by Deka Ironwork Simulations and Eagle Dynamics", "China Asset Pack"},
		{"USS_Nimitz", "Supercarrier"},
		{"Currenthill Assets Pack", "Currenthill Assets"},
		{"HeavyMetalCore", "Heavy Metal"},
		{"Massun92-Assetpack", "Massun92 Assets"},
		{"RailwayObjectsPack", "Railway Objects"},
		{"South_Atlantic_Assets", "South Atlantic Assets"},
		{"TechWeaponPack", "Tech Weapon Pack"},
		{"C-130-Assets", "C-130 Assets"},
		{"C-130J AI", "C-130 Assets"},
		{"Mirage F1 Assets by Aerges", "Mirage F1 Assets"},
		{"Animals", "Animals"},
		{"NS430", "NS430"},

		// Per-aircraft AI mods → no label (treated as base-equivalent per D7)
		{"F-14B AI by Heatblur Simulations", ""},
		{"Mi-24P AI by Eagle Dynamics", ""},
		{"AV-8B N/A AI by RAZBAM Sims", ""},
		{"F-16C bl.50 AI", ""},

		// Empty / base-game
		{"", ""},
	}
	for _, c := range cases {
		got := OriginLabel(c.raw)
		if got != c.want {
			t.Errorf("OriginLabel(%q) = %q, want %q", c.raw, got, c.want)
		}
	}
}
