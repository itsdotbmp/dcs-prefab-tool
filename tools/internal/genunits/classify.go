package genunits

// Bucket is the destination namespace for an Entry. Top is "units" or
// "statics". Cat is the category sub-namespace (e.g. "armor", "ships").
// Sub is the third-level sub-bucket where the catalog uses one
// (e.g. "tanks" under armor, "carriers" under ships); empty otherwise.
type Bucket struct {
	Top string
	Cat string
	Sub string
}

// IsZero reports whether the bucket is the zero value (used for entries
// that should be skipped from output entirely, such as those in folders
// the catalog does not surface).
func (b Bucket) IsZero() bool { return b == Bucket{} }

// Classify routes an Entry into a Bucket per spec D8. Returns the zero
// Bucket in two cases:
//
//   - Explicit skip: entries from folders the catalog deliberately omits
//     (currently only "GT_t", which is internal/generic table data).
//   - Unrecognized folder: entries whose Folder doesn't match any known
//     case. The orchestrator (genunits.Run) is expected to log a warning
//     to stderr when this happens so future DCS additions surface clearly.
//
// The two cases are not currently distinguished in the return value;
// callers that need to differentiate should check Folder against the
// explicit-skip set first.
func Classify(e Entry) Bucket {
	switch e.Folder {
	case "Planes":
		return Bucket{Top: "units", Cat: "planes"}
	case "Helicopters":
		return Bucket{Top: "units", Cat: "helicopters"}
	case "Cars":
		return classifyGround(e)
	case "Ships":
		return classifyShip(e)

	// Statics
	case "Fortifications":
		return Bucket{Top: "statics", Cat: "fortifications"}
	case "Cargos":
		return Bucket{Top: "statics", Cat: "cargos"}
	case "Personnel":
		return Bucket{Top: "statics", Cat: "personnel"}
	case "Heliports":
		return Bucket{Top: "statics", Cat: "heliports"}
	case "Warehouses":
		return Bucket{Top: "statics", Cat: "warehouses"}
	case "GrassAirfields":
		return Bucket{Top: "statics", Cat: "airfields"}
	case "ADEquipments":
		return Bucket{Top: "statics", Cat: "equipment"}
	case "Effects":
		return Bucket{Top: "statics", Cat: "effects"}
	case "Animals":
		return Bucket{Top: "statics", Cat: "animals"}
	case "LTAvehicles":
		return Bucket{Top: "statics", Cat: "airships"}
	case "GroundObjects":
		return Bucket{Top: "statics", Cat: "ground_objects"}

	// Internal / not user-facing
	case "GT_t":
		return Bucket{}
	}
	return Bucket{}
}

func classifyGround(e Entry) Bucket {
	switch e.Category {
	case "Armor":
		switch {
		case hasAttr(e, "Tanks"):
			return Bucket{"units", "armor", "tanks"}
		case hasAttr(e, "IFV"):
			return Bucket{"units", "armor", "ifv"}
		case hasAttr(e, "APC"):
			return Bucket{"units", "armor", "apc"}
		default:
			return Bucket{"units", "armor", "misc"}
		}
	case "Air Defence":
		switch {
		case hasAttr(e, "MANPADS"), hasAttr(e, "MANPADS AUX"):
			return Bucket{"units", "air_defence", "manpads"}
		case hasAttr(e, "AAA"), hasAttr(e, "AA_flak"):
			return Bucket{"units", "air_defence", "aaa"}
		case hasAttr(e, "EWR"):
			return Bucket{"units", "air_defence", "radar"}
		case hasAttr(e, "AA_missile"),
			hasAttr(e, "SAM LL"),
			hasAttr(e, "SAM SR"),
			hasAttr(e, "SAM TR"),
			hasAttr(e, "LR SAM"),
			hasAttr(e, "SR SAM"):
			return Bucket{"units", "air_defence", "sam"}
		default:
			return Bucket{"units", "air_defence", "misc"}
		}
	case "Artillery":
		return Bucket{Top: "units", Cat: "artillery"}
	case "Infantry":
		return Bucket{Top: "units", Cat: "infantry"}
	case "Unarmed":
		return Bucket{Top: "units", Cat: "unarmed"}
	case "MissilesSS":
		return Bucket{Top: "units", Cat: "missiles"}
	case "Carriage", "Locomotive", "Train":
		return Bucket{Top: "units", Cat: "trains"}
	case "Fortification":
		// Datamine ships a handful of Fortification-category entries inside
		// Cars/Car/ (e.g. Bunker, Sandbox, outpost). Despite the "static"
		// feel, they carry the "Ground Units" attribute and are spawned via
		// coalition.addGroup — not coalition.addStaticObject — so they
		// belong on the units side, parallel to unarmed/infantry.
		return Bucket{Top: "units", Cat: "fortifications"}
	}
	return Bucket{}
}

func classifyShip(e Entry) Bucket {
	switch {
	case hasAttr(e, "Aircraft Carriers"), hasAttr(e, "AircraftCarrier"):
		return Bucket{"units", "ships", "carriers"}
	case hasAttr(e, "Submarines"):
		return Bucket{"units", "ships", "submarines"}
	case hasAttr(e, "Unarmed ships"), !hasAttr(e, "Armed ships"):
		return Bucket{"units", "ships", "civilian"}
	default:
		return Bucket{"units", "ships", "warships"}
	}
}

func hasAttr(e Entry, want string) bool {
	for _, a := range e.Attributes {
		if a == want {
			return true
		}
	}
	return false
}
