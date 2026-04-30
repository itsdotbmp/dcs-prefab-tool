// Package genunits parses dcs-lua-datamine and emits framework/units.lua
// and framework/statics.lua. The pipeline is:
//
//   parse  → []Entry                              (parser.go)
//   classify each entry into a bucket             (classify.go)
//   sanitize each Type into a Lua identifier      (sanitize.go)
//   resolve each Origin to a friendly label       (origin.go)
//   emit Lua files                                (emit.go)
//
// See docs/superpowers/specs/2026-04-30-units-statics-catalog.md for the
// complete design including classification rules (D8) and origin labels (D7).
package genunits

// Entry is one parsed datamine record — a single spawnable DCS type.
// All fields except Type may be empty if the source file did not declare them;
// classification rules are responsible for handling those gracefully.
type Entry struct {
	// Type is the verbatim DCS type-string used by coalition.addGroup
	// (e.g. "F-16C_50", "T-72B", "Bunker"). Required.
	Type string

	// Category is the per-unit category field from the datamine
	// (e.g. "Armor", "Air Defence", "Infantry", "Carriage").
	// Empty for planes/helicopters/ships/statics — only ground entries set it.
	Category string

	// Attributes is the attribute array from the datamine (mixed-type;
	// we keep only the string entries — numeric IDs at the front are dropped).
	Attributes []string

	// Origin is the _origin field, used to derive the comment label.
	// Empty for base-game entries.
	Origin string

	// Folder is the top-level folder under _G/db/Units/ where the file lived
	// (e.g. "Planes", "Cars", "Helicopters", "Ships", "Fortifications").
	// Drives top-level routing in the classifier.
	Folder string

	// SourcePath is the absolute path of the datamine file the entry came
	// from. Diagnostic-only — used in error messages.
	SourcePath string
}

// Options configures a generator run.
type Options struct {
	// DatamineRoot is the path to the dcs-lua-datamine repo root
	// (the directory that contains _G/).
	DatamineRoot string

	// OutDir is where framework/units.lua and framework/statics.lua are
	// written. Typically <repo>/framework.
	OutDir string

	// Now is injected for deterministic test output. Production callers
	// can leave it zero — Run will substitute time.Now().
	Now string

	// DatamineCommit is the dcs-lua-datamine git SHA for the header banner.
	// May be empty.
	DatamineCommit string
}

// Run executes the full pipeline. Returns the number of entries emitted to
// each file (units, statics) and any error.
func Run(opts Options) (units, statics int, err error) {
	// Implementation lands in Task 7 once parser, classifier, sanitizer,
	// origin mapper, and emitter are in place. Stub for now so the package
	// compiles and tests can import it.
	return 0, 0, nil
}
