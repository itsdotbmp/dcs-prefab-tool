package genunits

import "testing"

// classifyTest is one routing case: an Entry shape that should land in the
// expected Bucket. The Bucket type lives in classify.go.
type classifyTest struct {
	name string
	in   Entry
	want Bucket
}

func TestClassify_routing(t *testing.T) {
	cases := []classifyTest{
		// Aircraft (folder = Planes)
		{"plane fighter", Entry{Type: "F-15C", Folder: "Planes", Attributes: []string{"Fighters", "Air", "Planes"}}, Bucket{Top: "units", Cat: "planes"}},
		{"plane bomber", Entry{Type: "B-52H", Folder: "Planes", Attributes: []string{"Strategic bombers", "Air", "Planes"}}, Bucket{Top: "units", Cat: "planes"}},

		// Helicopters
		{"helo", Entry{Type: "AH-64D", Folder: "Helicopters", Attributes: []string{"Attack helicopters", "Air", "Helicopters"}}, Bucket{Top: "units", Cat: "helicopters"}},

		// Ground — armor
		{"tank", Entry{Type: "T-72B", Folder: "Cars", Category: "Armor", Attributes: []string{"Tanks"}}, Bucket{Top: "units", Cat: "armor", Sub: "tanks"}},
		{"ifv", Entry{Type: "BMP-2", Folder: "Cars", Category: "Armor", Attributes: []string{"IFV"}}, Bucket{Top: "units", Cat: "armor", Sub: "ifv"}},
		{"apc", Entry{Type: "BTR-80", Folder: "Cars", Category: "Armor", Attributes: []string{"APC"}}, Bucket{Top: "units", Cat: "armor", Sub: "apc"}},
		{"armor misc", Entry{Type: "Strange-thing", Folder: "Cars", Category: "Armor", Attributes: []string{"Armored vehicles"}}, Bucket{Top: "units", Cat: "armor", Sub: "misc"}},

		// Ground — air defence
		{"sam-ll", Entry{Type: "S-300PS 5P85C ln", Folder: "Cars", Category: "Air Defence", Attributes: []string{"AA_missile", "SAM LL"}}, Bucket{Top: "units", Cat: "air_defence", Sub: "sam"}},
		{"sam-sr", Entry{Type: "S-300PS 64H6E sr", Folder: "Cars", Category: "Air Defence", Attributes: []string{"LR SAM", "SAM SR"}}, Bucket{Top: "units", Cat: "air_defence", Sub: "sam"}},
		{"aaa", Entry{Type: "ZSU-23-4 Shilka", Folder: "Cars", Category: "Air Defence", Attributes: []string{"AA_flak", "Mobile AAA", "AAA"}}, Bucket{Top: "units", Cat: "air_defence", Sub: "aaa"}},
		{"manpads", Entry{Type: "Stinger comm", Folder: "Cars", Category: "Air Defence", Attributes: []string{"MANPADS AUX", "Infantry"}}, Bucket{Top: "units", Cat: "air_defence", Sub: "manpads"}},
		{"radar EWR attribute", Entry{Type: "1L13 EWR", Folder: "Cars", Category: "Air Defence", Attributes: []string{"EWR"}}, Bucket{Top: "units", Cat: "air_defence", Sub: "radar"}},
		{"ad misc", Entry{Type: "Some Generator", Folder: "Cars", Category: "Air Defence", Attributes: []string{"SAM elements"}}, Bucket{Top: "units", Cat: "air_defence", Sub: "misc"}},

		// Ground — flat sub-categories
		{"artillery", Entry{Type: "M-109", Folder: "Cars", Category: "Artillery", Attributes: []string{"Artillery"}}, Bucket{Top: "units", Cat: "artillery"}},
		{"infantry", Entry{Type: "Soldier M4", Folder: "Cars", Category: "Infantry", Attributes: []string{"Infantry"}}, Bucket{Top: "units", Cat: "infantry"}},
		{"unarmed", Entry{Type: "Hummer", Folder: "Cars", Category: "Unarmed", Attributes: []string{"APC"}}, Bucket{Top: "units", Cat: "unarmed"}},
		{"missiles", Entry{Type: "Scud_B", Folder: "Cars", Category: "MissilesSS", Attributes: []string{"SS_missile"}}, Bucket{Top: "units", Cat: "missiles"}},

		// Trains
		{"train (carriage)", Entry{Type: "Coach cargo", Folder: "Cars", Category: "Carriage"}, Bucket{Top: "units", Cat: "trains"}},
		{"train (locomotive)", Entry{Type: "Locomotive", Folder: "Cars", Category: "Locomotive"}, Bucket{Top: "units", Cat: "trains"}},
		{"train (Train)", Entry{Type: "Train", Folder: "Cars", Category: "Train"}, Bucket{Top: "units", Cat: "trains"}},

		// Ships
		{"ship carrier", Entry{Type: "CVN_71", Folder: "Ships", Attributes: []string{"Aircraft Carriers", "Armed ships"}}, Bucket{Top: "units", Cat: "ships", Sub: "carriers"}},
		{"ship sub", Entry{Type: "KILO", Folder: "Ships", Attributes: []string{"Submarines"}}, Bucket{Top: "units", Cat: "ships", Sub: "submarines"}},
		{"ship civilian (Unarmed ships)", Entry{Type: "HandyWind", Folder: "Ships", Attributes: []string{"Unarmed ships"}}, Bucket{Top: "units", Cat: "ships", Sub: "civilian"}},
		{"ship civilian (no Armed ships)", Entry{Type: "Tug", Folder: "Ships", Attributes: []string{"Vessels"}}, Bucket{Top: "units", Cat: "ships", Sub: "civilian"}},
		{"ship warship", Entry{Type: "MOSCOW", Folder: "Ships", Attributes: []string{"Cruisers", "Armed ships"}}, Bucket{Top: "units", Cat: "ships", Sub: "warships"}},

		// Statics
		{"fortifications", Entry{Type: "Bunker", Folder: "Fortifications"}, Bucket{Top: "statics", Cat: "fortifications"}},
		{"cargos", Entry{Type: "container_20ft", Folder: "Cargos"}, Bucket{Top: "statics", Cat: "cargos"}},
		{"personnel", Entry{Type: "us carrier tech", Folder: "Personnel"}, Bucket{Top: "statics", Cat: "personnel"}},
		{"heliports", Entry{Type: "FARP", Folder: "Heliports"}, Bucket{Top: "statics", Cat: "heliports"}},
		{"warehouses", Entry{Type: "Warehouse", Folder: "Warehouses"}, Bucket{Top: "statics", Cat: "warehouses"}},
		{"airfields", Entry{Type: "GrassAirfield", Folder: "GrassAirfields"}, Bucket{Top: "statics", Cat: "airfields"}},
		{"equipment", Entry{Type: "Generator F", Folder: "ADEquipments"}, Bucket{Top: "statics", Cat: "equipment"}},
		{"effects", Entry{Type: "big_smoke", Folder: "Effects"}, Bucket{Top: "statics", Cat: "effects"}},
		{"animals", Entry{Type: "Cow", Folder: "Animals"}, Bucket{Top: "statics", Cat: "animals"}},
		{"airships", Entry{Type: "Tethered balloon", Folder: "LTAvehicles"}, Bucket{Top: "statics", Cat: "airships"}},
		{"ground objects", Entry{Type: "Some Object", Folder: "GroundObjects"}, Bucket{Top: "statics", Cat: "ground_objects"}},

		// Skipped folders return zero-value Bucket
		{"GT_t skipped", Entry{Type: "Whatever", Folder: "GT_t"}, Bucket{}},
	}
	for _, c := range cases {
		got := Classify(c.in)
		if got != c.want {
			t.Errorf("%s: Classify(...) = %+v, want %+v", c.name, got, c.want)
		}
	}
}
