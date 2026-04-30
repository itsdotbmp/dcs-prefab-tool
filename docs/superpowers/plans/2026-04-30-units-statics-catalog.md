# Units & statics catalog — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `sms.units.*` and `sms.statics.*` catalogs of every DCS spawnable type, generated from `dcs-lua-datamine` via a new `dcs-sms gen-units` CLI sub-command, with `origin_of` lookup, LuaCATS aliases, smoke tests, and docs.

**Architecture:** Go package `tools/internal/genunits/` parses the datamine, classifies entries into bucketed Lua tables per the spec's D8 routing rules, emits `framework/units.lua` and `framework/statics.lua`. The CLI surface is a sub-command on the existing `dcs-sms` binary. The generated Lua files load via `framework/load_all.lua` like every other module. Failure model is the framework standard (`origin_of` returns silent nil; catalog tables are inert data).

**Tech Stack:** Go 1.22, Lua 5.1 (mission environment), bash smoke tests driven by `tools/dcs-sms.exe`, LuaCATS annotations.

**Spec:** `docs/superpowers/specs/2026-04-30-units-statics-catalog.md`

---

## Conventions used in this plan

- **Working directory:** `D:/git/dcs-sms/.worktrees/units-statics-catalog/`. All shell commands run from there (or the appropriate sub-directory called out per task) unless otherwise noted.
- **Datamine path:** `D:/git/dcs-lua-datamine`. Tests use small fixture files under `tools/internal/genunits/testdata/`; only Task 9 reads the real datamine.
- **Go test commands:** run from `tools/`, e.g. `go test ./internal/genunits/...`.
- **Commit style:** conventional commits, scopes follow the repo (`feat(genunits)`, `feat(framework)`, `docs(framework)`, etc.). One commit per task unless a step says otherwise.

---

### Task 1: Generator package skeleton + `Entry` type

**Files:**
- Create: `tools/internal/genunits/genunits.go`
- Create: `tools/internal/genunits/genunits_test.go`

- [ ] **Step 1: Create the package skeleton with the `Entry` type**

Create `tools/internal/genunits/genunits.go`:

```go
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
```

- [ ] **Step 2: Write a stub smoke test for the package**

Create `tools/internal/genunits/genunits_test.go`:

```go
package genunits

import "testing"

func TestEntryZeroValue(t *testing.T) {
	var e Entry
	if e.Type != "" || e.Category != "" || len(e.Attributes) != 0 || e.Origin != "" || e.Folder != "" {
		t.Errorf("expected zero Entry to have empty fields, got %+v", e)
	}
}

func TestRunStubReturnsNoError(t *testing.T) {
	_, _, err := Run(Options{})
	if err != nil {
		t.Errorf("stub Run should not error, got %v", err)
	}
}
```

- [ ] **Step 3: Verify the package builds and tests pass**

Run from `tools/`:
```
go test ./internal/genunits/...
```
Expected: `ok  github.com/nielsvaes/dcs-sms/tools/internal/genunits`.

- [ ] **Step 4: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add tools/internal/genunits/genunits.go tools/internal/genunits/genunits_test.go
git commit -m "feat(genunits): scaffold package with Entry and Options types"
```

---

### Task 2: Datamine parser

**Files:**
- Create: `tools/internal/genunits/parser.go`
- Create: `tools/internal/genunits/parser_test.go`
- Create: `tools/internal/genunits/testdata/Units/Planes/Plane/F-16C_50.lua`
- Create: `tools/internal/genunits/testdata/Units/Cars/Car/T-72B.lua`
- Create: `tools/internal/genunits/testdata/Units/Cars/Car/Soldier M4.lua`
- Create: `tools/internal/genunits/testdata/Units/Cars/Car/T-80B.lua`
- Create: `tools/internal/genunits/testdata/Units/Fortifications/Fortification/Bunker.lua`

- [ ] **Step 1: Create test fixtures**

Each fixture is a trimmed-down version of the real datamine entry — only the four fields the parser cares about, plus a couple of red-herrings to verify it ignores them.

Create `tools/internal/genunits/testdata/Units/Planes/Plane/F-16C_50.lua`:

```lua
_G["db"]["Units"]["Planes"]["Plane"]["#Index"] = {
	Name = "F-16C 50",
	DisplayName = "F-16C bl.50",
	attribute = { 1, 1, 1, "Redacted", "Multirole fighters", "Refuelable", "Air", "Planes", "Battle airplanes" },
	type = "F-16C_50",
	WS = {
		LN = {
			-- nested table; parser must NOT pick up any "type" / "category"
			-- fields that may appear deeper in the structure.
			type = "ignore-me-i-am-nested",
		},
	},
}
```

Create `tools/internal/genunits/testdata/Units/Cars/Car/T-72B.lua`:

```lua
_G["db"]["Units"]["Cars"]["Car"]["#Index"] = {
	Name = "MBT T-72B",
	attribute = { 2, 17, 26, "Redacted", "Tanks", "Modern Tanks", "Armored vehicles", "Ground Units", "HeavyArmoredUnits" },
	category = "Armor",
	type = "T-72B",
}
```

Create `tools/internal/genunits/testdata/Units/Cars/Car/Soldier M4.lua`:

```lua
_G["db"]["Units"]["Cars"]["Car"]["#Index"] = {
	Name = "Infantry M4",
	attribute = { 2, 17, 26, "Redacted", "Infantry", "Ground Units" },
	category = "Infantry",
	type = "Soldier M4",
}
```

Create `tools/internal/genunits/testdata/Units/Cars/Car/T-80B.lua`:

```lua
_G["db"]["Units"]["Cars"]["Car"]["#Index"] = {
	Name = "MBT T-80B",
	attribute = { 2, 17, 26, "Redacted", "Tanks", "Modern Tanks", "Armored vehicles", "Ground Units", "HeavyArmoredUnits" },
	category = "Armor",
	type = "T-80B",
	_origin = "ColdWarAssetsPack",
}
```

Create `tools/internal/genunits/testdata/Units/Fortifications/Fortification/Bunker.lua`:

```lua
_G["db"]["Units"]["Fortifications"]["Fortification"]["#Index"] = {
	Name = "Bunker",
	attribute = { 4, 18, 33, "Buildings" },
	category = "Fortification",
	type = "Bunker",
}
```

- [ ] **Step 2: Write the failing parser tests**

Create `tools/internal/genunits/parser_test.go`:

```go
package genunits

import (
	"path/filepath"
	"sort"
	"testing"
)

func TestWalk_extractsAllTopLevelFields(t *testing.T) {
	root := filepath.Join("testdata")
	entries, err := Walk(root)
	if err != nil {
		t.Fatalf("Walk: %v", err)
	}
	if len(entries) != 5 {
		t.Fatalf("expected 5 entries (one per fixture), got %d", len(entries))
	}

	// Index by Type for stable lookup
	got := map[string]Entry{}
	for _, e := range entries {
		got[e.Type] = e
	}

	cases := []struct {
		typeStr   string
		category  string
		folder    string
		origin    string
		hasAttr   string
	}{
		{"F-16C_50", "", "Planes", "", "Multirole fighters"},
		{"T-72B", "Armor", "Cars", "", "Tanks"},
		{"Soldier M4", "Infantry", "Cars", "", "Infantry"},
		{"T-80B", "Armor", "Cars", "ColdWarAssetsPack", "Tanks"},
		{"Bunker", "Fortification", "Fortifications", "", "Buildings"},
	}
	for _, c := range cases {
		e, ok := got[c.typeStr]
		if !ok {
			t.Errorf("missing entry %q", c.typeStr)
			continue
		}
		if e.Category != c.category {
			t.Errorf("%s: Category=%q want %q", c.typeStr, e.Category, c.category)
		}
		if e.Folder != c.folder {
			t.Errorf("%s: Folder=%q want %q", c.typeStr, e.Folder, c.folder)
		}
		if e.Origin != c.origin {
			t.Errorf("%s: Origin=%q want %q", c.typeStr, e.Origin, c.origin)
		}
		// Attributes contain numeric IDs at the front; we keep strings only.
		if !contains(e.Attributes, c.hasAttr) {
			t.Errorf("%s: attributes %v missing %q", c.typeStr, e.Attributes, c.hasAttr)
		}
	}
}

func TestWalk_ignoresNestedTypeFields(t *testing.T) {
	entries, err := Walk(filepath.Join("testdata"))
	if err != nil {
		t.Fatalf("Walk: %v", err)
	}
	for _, e := range entries {
		if e.Type == "ignore-me-i-am-nested" {
			t.Errorf("parser picked up nested type field from %s", e.SourcePath)
		}
	}
}

func TestWalk_returnsEntriesSortedByPath(t *testing.T) {
	entries, err := Walk(filepath.Join("testdata"))
	if err != nil {
		t.Fatalf("Walk: %v", err)
	}
	paths := make([]string, len(entries))
	for i, e := range entries {
		paths[i] = e.SourcePath
	}
	sorted := append([]string(nil), paths...)
	sort.Strings(sorted)
	for i := range paths {
		if paths[i] != sorted[i] {
			t.Errorf("entries not sorted by path: index %d got %q want %q", i, paths[i], sorted[i])
		}
	}
}

func contains(s []string, want string) bool {
	for _, v := range s {
		if v == want {
			return true
		}
	}
	return false
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run from `tools/`:
```
go test ./internal/genunits/... -run TestWalk
```
Expected: FAIL — `Walk` undefined.

- [ ] **Step 4: Implement the parser**

Create `tools/internal/genunits/parser.go`:

```go
package genunits

import (
	"bufio"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Walk traverses datamineRoot and returns one Entry per .lua file found
// under <root>/_G/db/Units/.../**/*.lua.
//
// Each file is expected to contain exactly one top-level table assignment
// of the form:
//
//	_G["db"]["Units"]["<Folder>"]["<sub>"]["#Index"] = { ... }
//
// or
//
//	_G["db"]["Units"]["<Folder>"]["<key>"] = { ... }
//
// The parser extracts type, category, attribute, and _origin from the
// top-level fields (single-tab indent) and ignores anything deeper.
//
// Entries are returned sorted by SourcePath for deterministic output.
func Walk(datamineRoot string) ([]Entry, error) {
	unitsDir := filepath.Join(datamineRoot, "_G", "db", "Units")
	if _, err := os.Stat(unitsDir); err != nil {
		// Tolerate the case where the test fixture is rooted directly at
		// "testdata" (i.e. testdata/Units/...) without the _G/db wrapper.
		alt := filepath.Join(datamineRoot, "Units")
		if _, err2 := os.Stat(alt); err2 == nil {
			unitsDir = alt
		} else {
			return nil, fmt.Errorf("genunits: datamine root has neither _G/db/Units nor Units: %w", err)
		}
	}

	var entries []Entry
	err := filepath.WalkDir(unitsDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(d.Name(), ".lua") {
			return nil
		}
		e, ok, perr := parseFile(path, unitsDir)
		if perr != nil {
			return fmt.Errorf("parse %s: %w", path, perr)
		}
		if !ok {
			return nil // file had no parseable type field (e.g. helper files)
		}
		entries = append(entries, e)
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].SourcePath < entries[j].SourcePath })
	return entries, nil
}

// Top-level field patterns. We match `^\t<name> = ...` — single-tab indent
// only — so nested tables (deeper indentation) are ignored. The datamine
// uses tabs consistently; if a file ever shows up with spaces, fall through
// to the alternative pattern.
var (
	typeRe    = regexp.MustCompile(`^[\t ]?type = "(.*?)",`)
	categoryRe = regexp.MustCompile(`^[\t ]?category = "(.*?)",`)
	attrRe     = regexp.MustCompile(`^[\t ]?attribute = \{(.*)\},`)
	originRe   = regexp.MustCompile(`^[\t ]?_origin = "(.*?)",`)

	// Inside an attribute array, pull out every quoted string. Numeric IDs
	// at the front are ignored.
	attrStringRe = regexp.MustCompile(`"([^"]*)"`)
)

func parseFile(path, unitsRoot string) (Entry, bool, error) {
	f, err := os.Open(path)
	if err != nil {
		return Entry{}, false, err
	}
	defer f.Close()

	rel, err := filepath.Rel(unitsRoot, path)
	if err != nil {
		rel = path
	}
	folder := strings.SplitN(filepath.ToSlash(rel), "/", 2)[0]

	e := Entry{Folder: folder, SourcePath: path}

	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 1024*1024), 1024*1024) // some attribute lines are long

	for scanner.Scan() {
		line := scanner.Text()

		// Only top-level fields — we look at lines that begin with a tab
		// and a known field name. parseFile skips lines that begin with
		// more whitespace (nested tables).
		if !strings.HasPrefix(line, "\t") {
			continue
		}
		if strings.HasPrefix(line, "\t\t") {
			continue
		}

		if m := typeRe.FindStringSubmatch(line); m != nil && e.Type == "" {
			e.Type = m[1]
			continue
		}
		if m := categoryRe.FindStringSubmatch(line); m != nil && e.Category == "" {
			e.Category = m[1]
			continue
		}
		if m := originRe.FindStringSubmatch(line); m != nil && e.Origin == "" {
			e.Origin = m[1]
			continue
		}
		if m := attrRe.FindStringSubmatch(line); m != nil && e.Attributes == nil {
			for _, sm := range attrStringRe.FindAllStringSubmatch(m[1], -1) {
				e.Attributes = append(e.Attributes, sm[1])
			}
			continue
		}
	}
	if err := scanner.Err(); err != nil {
		return Entry{}, false, err
	}
	if e.Type == "" {
		return Entry{}, false, nil
	}
	return e, true, nil
}
```

Note on the regex: `^[\t ]?` is a workaround for files that occasionally start a top-level field with a leading space instead of a tab. The `\t\t` strip-prefix above catches the deeply-nested case.

- [ ] **Step 5: Run tests to verify they pass**

Run from `tools/`:
```
go test ./internal/genunits/... -run TestWalk
```
Expected: PASS for all three TestWalk_* tests.

- [ ] **Step 6: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add tools/internal/genunits/parser.go tools/internal/genunits/parser_test.go tools/internal/genunits/testdata
git commit -m "feat(genunits): add datamine parser with field extraction"
```

---

### Task 3: Sanitizer

**Files:**
- Create: `tools/internal/genunits/sanitize.go`
- Create: `tools/internal/genunits/sanitize_test.go`

- [ ] **Step 1: Write the failing sanitizer tests**

Create `tools/internal/genunits/sanitize_test.go`:

```go
package genunits

import (
	"sort"
	"testing"
)

func TestSanitizeIdentifier(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		// Common cases
		{"F-16C_50", "F_16C_50"},
		{"F-15C", "F_15C"},
		{"T-72B", "T_72B"},
		{"BMP-2", "BMP_2"},
		{"AH-64D_BLK_II", "AH_64D_BLK_II"},
		// Spaces
		{"Bf 109 K-4", "Bf_109_K_4"},
		{"Soldier M4", "Soldier_M4"},
		{"S-300PS 5P85C ln", "S_300PS_5P85C_ln"},
		// Slashes
		{"AV-8B N/A", "AV_8B_N_A"},
		// Dots
		{"F-16C bl.50", "F_16C_bl_50"},
		// Leading digit
		{"2B11 mortar", "_2B11_mortar"},
		{"55G6 EWR", "_55G6_EWR"},
		// Quotes and trailing space
		{`SAM SA-19 Tunguska "Grison" `, "SAM_SA_19_Tunguska_Grison_"},
		// Already an identifier (no-op except leading-digit prefix)
		{"Cow", "Cow"},
		{"ZSU_23_4_Shilka", "ZSU_23_4_Shilka"},
	}
	for _, c := range cases {
		got := SanitizeIdentifier(c.in)
		if got != c.want {
			t.Errorf("Sanitize(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestSanitizeIdentifier_collapsesRuns(t *testing.T) {
	// Multiple separators in a row collapse to a single underscore.
	got := SanitizeIdentifier("a---b///c   d")
	want := "a_b_c_d"
	if got != want {
		t.Errorf("Sanitize collapse: got %q, want %q", got, want)
	}
}

func TestResolveCollisions_appendsSuffixDeterministically(t *testing.T) {
	// Two distinct DCS strings that sanitize to the same identifier
	// should both be retained, with deterministic _2/_3 suffixing in
	// lexical order of the original strings.
	in := []string{"Foo Bar", "Foo-Bar", "Foo/Bar"}
	sort.Strings(in)
	got := ResolveCollisions(in)
	want := map[string]string{
		"Foo Bar": "Foo_Bar",   // first lexically
		"Foo-Bar": "Foo_Bar_2", // second
		"Foo/Bar": "Foo_Bar_3", // third
	}
	if len(got) != len(want) {
		t.Fatalf("size mismatch: got %d, want %d", len(got), len(want))
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("collision[%q]: got %q, want %q", k, got[k], v)
		}
	}
}

func TestResolveCollisions_idempotentAcrossCalls(t *testing.T) {
	in := []string{"X-1", "X 1", "X.1"}
	sort.Strings(in)
	a := ResolveCollisions(in)
	b := ResolveCollisions(in)
	if len(a) != len(b) {
		t.Fatalf("size differs across calls: %d vs %d", len(a), len(b))
	}
	for k := range a {
		if a[k] != b[k] {
			t.Errorf("non-deterministic for %q: %q vs %q", k, a[k], b[k])
		}
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run from `tools/`:
```
go test ./internal/genunits/... -run "TestSanitize|TestResolve"
```
Expected: FAIL — `SanitizeIdentifier` / `ResolveCollisions` undefined.

- [ ] **Step 3: Implement the sanitizer**

Create `tools/internal/genunits/sanitize.go`:

```go
package genunits

import (
	"sort"
	"strconv"
	"strings"
)

// SanitizeIdentifier converts a DCS type-string into a Lua identifier:
//   1. Replace every non-[a-zA-Z0-9_] character with _.
//   2. Collapse runs of _ to a single _.
//   3. If the result starts with a digit, prefix _.
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run from `tools/`:
```
go test ./internal/genunits/... -run "TestSanitize|TestResolve"
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add tools/internal/genunits/sanitize.go tools/internal/genunits/sanitize_test.go
git commit -m "feat(genunits): add identifier sanitizer with collision resolution"
```

---

### Task 4: Origin label mapper

**Files:**
- Create: `tools/internal/genunits/origin.go`
- Create: `tools/internal/genunits/origin_test.go`

- [ ] **Step 1: Write the failing origin tests**

Create `tools/internal/genunits/origin_test.go`:

```go
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run from `tools/`:
```
go test ./internal/genunits/... -run TestOriginLabel
```
Expected: FAIL — `OriginLabel` undefined.

- [ ] **Step 3: Implement origin label mapping**

Create `tools/internal/genunits/origin.go`:

```go
package genunits

import "strings"

// originLabels maps the verbatim _origin field to the user-facing comment
// label per spec decision D7. Entries not in this table either map to the
// empty string (no comment, no origin lookup) — handled in OriginLabel by
// the AI-mod heuristic.
var originLabels = map[string]string{
	"ColdWarAssetsPack":                                                      "Cold War Asset Pack",
	"WWII Armour and Technics":                                               "WWII Assets",
	"World War II AI Units by Eagle Dynamics":                                "WWII Assets",
	"World War II PTO Units by Magnitude 3 LLC":                              "WWII Assets",
	"M3 WWII PTO units":                                                      "WWII Assets",
	"China Asset Pack by Deka Ironwork Simulations and Eagle Dynamics":       "China Asset Pack",
	"USS_Nimitz":                                                             "Supercarrier",
	"Currenthill Assets Pack":                                                "Currenthill Assets",
	"HeavyMetalCore":                                                         "Heavy Metal",
	"Massun92-Assetpack":                                                     "Massun92 Assets",
	"RailwayObjectsPack":                                                     "Railway Objects",
	"South_Atlantic_Assets":                                                  "South Atlantic Assets",
	"TechWeaponPack":                                                         "Tech Weapon Pack",
	"C-130-Assets":                                                           "C-130 Assets",
	"C-130J AI":                                                              "C-130 Assets",
	"Mirage F1 Assets by Aerges":                                             "Mirage F1 Assets",
	"Animals":                                                                "Animals",
	"NS430":                                                                  "NS430",
	"WWII Units":                                                             "WWII Assets",
	"TAVKR 1143 High Detail":                                                 "TAVKR 1143",
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run from `tools/`:
```
go test ./internal/genunits/... -run TestOriginLabel
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add tools/internal/genunits/origin.go tools/internal/genunits/origin_test.go
git commit -m "feat(genunits): add origin label mapping per spec D7"
```

---

### Task 5: Classifier

**Files:**
- Create: `tools/internal/genunits/classify.go`
- Create: `tools/internal/genunits/classify_test.go`

- [ ] **Step 1: Write the failing classifier tests**

Create `tools/internal/genunits/classify_test.go`:

```go
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run from `tools/`:
```
go test ./internal/genunits/... -run TestClassify
```
Expected: FAIL — `Classify` / `Bucket` undefined.

- [ ] **Step 3: Implement the classifier**

Create `tools/internal/genunits/classify.go`:

```go
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
// Bucket for entries that should be skipped (e.g. files under GT_t/).
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run from `tools/`:
```
go test ./internal/genunits/... -run TestClassify
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add tools/internal/genunits/classify.go tools/internal/genunits/classify_test.go
git commit -m "feat(genunits): add classifier with D8 routing rules"
```

---

### Task 6: Emitter

**Files:**
- Create: `tools/internal/genunits/emit.go`
- Create: `tools/internal/genunits/emit_test.go`

- [ ] **Step 1: Write the failing emitter tests**

Create `tools/internal/genunits/emit_test.go`:

```go
package genunits

import (
	"strings"
	"testing"
)

// EmitInputs wraps the args EmitUnits / EmitStatics need so the tests can
// build them up declaratively.
func sampleEmitInputs() ([]ClassifiedEntry, []ClassifiedEntry) {
	units := []ClassifiedEntry{
		{Bucket: Bucket{"units", "planes", ""}, Type: "F-16C_50", Identifier: "F_16C_50", OriginLabel: ""},
		{Bucket: Bucket{"units", "armor", "tanks"}, Type: "T-72B", Identifier: "T_72B", OriginLabel: ""},
		{Bucket: Bucket{"units", "armor", "tanks"}, Type: "T-80B", Identifier: "T_80B", OriginLabel: "Cold War Asset Pack"},
		{Bucket: Bucket{"units", "armor", "tanks"}, Type: "M-1 Abrams", Identifier: "M_1_Abrams", OriginLabel: ""},
		{Bucket: Bucket{"units", "armor", "ifv"}, Type: "BMP-2", Identifier: "BMP_2", OriginLabel: ""},
		{Bucket: Bucket{"units", "infantry", ""}, Type: "Soldier M4", Identifier: "Soldier_M4", OriginLabel: ""},
		{Bucket: Bucket{"units", "ships", "warships"}, Type: "MOSCOW", Identifier: "MOSCOW", OriginLabel: ""},
	}
	statics := []ClassifiedEntry{
		{Bucket: Bucket{"statics", "fortifications", ""}, Type: "Bunker", Identifier: "Bunker", OriginLabel: ""},
		{Bucket: Bucket{"statics", "animals", ""}, Type: "Cow", Identifier: "Cow", OriginLabel: ""},
	}
	return units, statics
}

func TestEmitUnits_outputShape(t *testing.T) {
	units, _ := sampleEmitInputs()
	var sb strings.Builder
	if err := EmitUnits(&sb, units, "fakecommit", "2026-04-30T00:00:00Z"); err != nil {
		t.Fatalf("EmitUnits: %v", err)
	}
	out := sb.String()

	mustContain := []string{
		// Header
		"-- AUTO-GENERATED",
		"dcs-lua-datamine @ fakecommit",
		"2026-04-30T00:00:00Z",
		// LuaCATS alias listing
		`---@alias sms.GroupSpawnType`,
		`---| "F-16C_50"`,
		`---| "M-1 Abrams"`,
		`---| "T-80B"`,
		// Tables — assignments (no embedded padding; spaces vary per-line)
		`sms.units = sms.units or {}`,
		`sms.units.planes = {`,
		`F_16C_50 = "F-16C_50",`,
		`sms.units.armor = {`,
		`tanks = {`,
		`T_72B = "T-72B",`,
		`T_80B = "T-80B",`,
		`M_1_Abrams = "M-1 Abrams",`,
		`ifv = {`,
		`BMP_2 = "BMP-2",`,
		`sms.units.infantry = {`,
		`Soldier_M4 = "Soldier M4",`,
		`sms.units.ships = {`,
		`warships = {`,
		`MOSCOW = "MOSCOW",`,
		// Origin label appears after the assignment, separated by padding
		`-- Cold War Asset Pack`,
		// origin_of helper + lookup table
		`local _origin = {`,
		`["T-80B"]`,
		`= "Cold War Asset Pack",`,
		`sms.units.origin_of = function`,
	}
	for _, want := range mustContain {
		if !strings.Contains(out, want) {
			t.Errorf("output missing %q\n--- output ---\n%s", want, out)
		}
	}
}

func TestEmitUnits_alphabeticalWithinBucket(t *testing.T) {
	units, _ := sampleEmitInputs()
	var sb strings.Builder
	if err := EmitUnits(&sb, units, "x", "y"); err != nil {
		t.Fatalf("EmitUnits: %v", err)
	}
	out := sb.String()
	// Within sms.units.armor.tanks, identifiers are alphabetical:
	// M_1_Abrams < T_72B < T_80B.
	idxA := strings.Index(out, `M_1_Abrams`)
	idxT72 := strings.Index(out, `T_72B`)
	idxT80 := strings.Index(out, `T_80B`)
	if idxA < 0 || idxT72 < 0 || idxT80 < 0 {
		t.Fatalf("missing tank entries in output")
	}
	if !(idxA < idxT72 && idxT72 < idxT80) {
		t.Errorf("expected M_1_Abrams < T_72B < T_80B in output, got positions %d, %d, %d", idxA, idxT72, idxT80)
	}
}

func TestEmitUnits_idempotent(t *testing.T) {
	units, _ := sampleEmitInputs()
	var a, b strings.Builder
	if err := EmitUnits(&a, units, "x", "y"); err != nil {
		t.Fatalf("EmitUnits a: %v", err)
	}
	if err := EmitUnits(&b, units, "x", "y"); err != nil {
		t.Fatalf("EmitUnits b: %v", err)
	}
	if a.String() != b.String() {
		t.Errorf("non-deterministic output across two runs")
	}
}

func TestEmitStatics_outputShape(t *testing.T) {
	_, statics := sampleEmitInputs()
	var sb strings.Builder
	if err := EmitStatics(&sb, statics, "x", "y"); err != nil {
		t.Fatalf("EmitStatics: %v", err)
	}
	out := sb.String()
	mustContain := []string{
		`---@alias sms.StaticSpawnType`,
		`---| "Bunker"`,
		`---| "Cow"`,
		`sms.statics = sms.statics or {}`,
		`sms.statics.fortifications = {`,
		`Bunker = "Bunker",`,
		`sms.statics.animals = {`,
		`Cow = "Cow",`,
		`sms.statics.origin_of = function`,
	}
	for _, want := range mustContain {
		if !strings.Contains(out, want) {
			t.Errorf("output missing %q\n--- output ---\n%s", want, out)
		}
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run from `tools/`:
```
go test ./internal/genunits/... -run TestEmit
```
Expected: FAIL — `EmitUnits`, `EmitStatics`, `ClassifiedEntry` undefined.

- [ ] **Step 3: Implement the emitter**

Create `tools/internal/genunits/emit.go`:

```go
package genunits

import (
	"fmt"
	"io"
	"sort"
	"strings"
)

// ClassifiedEntry is an Entry that has gone through Classify + Sanitize +
// origin lookup. It is the input to the emitter.
type ClassifiedEntry struct {
	Bucket      Bucket
	Type        string // verbatim DCS type-string (right-hand side of assignment)
	Identifier  string // sanitized Lua identifier (left-hand side of assignment)
	OriginLabel string // friendly origin label or "" for base-game
}

// EmitUnits writes the framework/units.lua source for the given classified
// entries (those with Bucket.Top == "units") to w.
func EmitUnits(w io.Writer, entries []ClassifiedEntry, datamineCommit, generatedAt string) error {
	return emit(w, entries, "units",
		"sms.units", "sms.GroupSpawnType",
		datamineCommit, generatedAt)
}

// EmitStatics writes framework/statics.lua source for the given classified
// entries (those with Bucket.Top == "statics") to w.
func EmitStatics(w io.Writer, entries []ClassifiedEntry, datamineCommit, generatedAt string) error {
	return emit(w, entries, "statics",
		"sms.statics", "sms.StaticSpawnType",
		datamineCommit, generatedAt)
}

func emit(w io.Writer, entries []ClassifiedEntry, top, ns, alias, commit, ts string) error {
	// Filter to the requested top-level namespace.
	var mine []ClassifiedEntry
	for _, e := range entries {
		if e.Bucket.Top == top {
			mine = append(mine, e)
		}
	}

	// Sort by identifier for deterministic output. Within a bucket, the
	// loop below relies on sorted-by-bucket-then-identifier order.
	sort.Slice(mine, func(i, j int) bool {
		ai, aj := mine[i].Bucket, mine[j].Bucket
		if ai.Cat != aj.Cat {
			return ai.Cat < aj.Cat
		}
		if ai.Sub != aj.Sub {
			return ai.Sub < aj.Sub
		}
		return mine[i].Identifier < mine[j].Identifier
	})

	// Header
	fmt.Fprintln(w, "-- AUTO-GENERATED by `dcs-sms gen-units`. Do not edit by hand.")
	fmt.Fprintf(w, "-- Source: dcs-lua-datamine @ %s  (regenerated %s)\n", commit, ts)
	fmt.Fprintf(w, "-- See docs/api/%s.md for usage.\n", top)
	fmt.Fprintln(w)
	fmt.Fprintln(w, `assert(type(sms) == "table", "framework/sms.lua must be loaded first")`)
	fmt.Fprintf(w, "local log = sms.log.module(%q)\n", ns)
	fmt.Fprintln(w)

	// LuaCATS alias — every type-string, alphabetical.
	types := make([]string, 0, len(mine))
	seenType := map[string]bool{}
	for _, e := range mine {
		if !seenType[e.Type] {
			types = append(types, e.Type)
			seenType[e.Type] = true
		}
	}
	sort.Strings(types)
	fmt.Fprintf(w, "---@alias %s\n", alias)
	for _, ty := range types {
		fmt.Fprintf(w, "---| %q\n", ty)
	}
	fmt.Fprintln(w)

	// Namespace declaration
	fmt.Fprintf(w, "---@class %s\n", ns)
	fmt.Fprintf(w, "%s = %s or {}\n", ns, ns)
	fmt.Fprintln(w)

	// Tables, grouped by Cat then Sub.
	type group struct {
		cat, sub string
		entries  []ClassifiedEntry
	}
	groups := []group{}
	for _, e := range mine {
		if len(groups) == 0 || groups[len(groups)-1].cat != e.Bucket.Cat || groups[len(groups)-1].sub != e.Bucket.Sub {
			groups = append(groups, group{cat: e.Bucket.Cat, sub: e.Bucket.Sub})
		}
		groups[len(groups)-1].entries = append(groups[len(groups)-1].entries, e)
	}

	// Emit one outer table per Cat. Sub-buckets are nested within.
	prevCat := ""
	openCat := false
	for i, g := range groups {
		if g.cat != prevCat {
			if openCat {
				fmt.Fprintln(w, "}")
				fmt.Fprintln(w)
			}
			fmt.Fprintf(w, "%s.%s = {\n", ns, g.cat)
			prevCat = g.cat
			openCat = true
		}
		// Sub-bucket header (only if this group has a sub)
		indent := "  "
		if g.sub != "" {
			fmt.Fprintf(w, "%s%s = {\n", indent, g.sub)
			indent = "    "
		}
		for _, e := range g.entries {
			line := fmt.Sprintf("%s%s = %q,", indent, e.Identifier, e.Type)
			if e.OriginLabel != "" {
				line = padToColumn(line, 60) + " -- " + e.OriginLabel
			}
			fmt.Fprintln(w, line)
		}
		if g.sub != "" {
			fmt.Fprintln(w, "  },")
		}
		// Look ahead: close the cat-table if next group is a different cat or this is the last group
		isLast := i == len(groups)-1
		if isLast || groups[i+1].cat != g.cat {
			fmt.Fprintln(w, "}")
			fmt.Fprintln(w)
			openCat = false
			prevCat = ""
		}
	}

	// origin_of helper
	fmt.Fprintln(w, "-- ============================================================")
	fmt.Fprintln(w, "-- Origin lookup")
	fmt.Fprintln(w, "-- ============================================================")
	fmt.Fprintln(w)
	fmt.Fprintln(w, "local _origin = {")
	originOrdered := append([]ClassifiedEntry(nil), mine...)
	sort.Slice(originOrdered, func(i, j int) bool { return originOrdered[i].Type < originOrdered[j].Type })
	for _, e := range originOrdered {
		if e.OriginLabel == "" {
			continue
		}
		fmt.Fprintf(w, "  [%q] = %q,\n", e.Type, e.OriginLabel)
	}
	fmt.Fprintln(w, "}")
	fmt.Fprintln(w)
	fmt.Fprintln(w, "---@param type_string string  DCS type-string to look up")
	fmt.Fprintln(w, "---@return string|nil  asset-pack label if non-base, nil otherwise")
	fmt.Fprintf(w, "%s.origin_of = function(type_string)\n", ns)
	fmt.Fprintln(w, "  if type(type_string) ~= \"string\" then return nil end")
	fmt.Fprintln(w, "  return _origin[type_string]")
	fmt.Fprintln(w, "end")

	return nil
}

// padToColumn returns s padded with spaces to at least width columns.
func padToColumn(s string, width int) string {
	if len(s) >= width {
		return s
	}
	return s + strings.Repeat(" ", width-len(s))
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run from `tools/`:
```
go test ./internal/genunits/... -run TestEmit
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add tools/internal/genunits/emit.go tools/internal/genunits/emit_test.go
git commit -m "feat(genunits): add Lua emitter with LuaCATS alias and origin_of helper"
```

---

### Task 7: Wire the orchestration

**Files:**
- Modify: `tools/internal/genunits/genunits.go`
- Modify: `tools/internal/genunits/genunits_test.go`

- [ ] **Step 1: Replace the stub `Run` with the real pipeline**

Replace `tools/internal/genunits/genunits.go` with:

```go
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

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"
)

// Entry is one parsed datamine record — a single spawnable DCS type.
type Entry struct {
	Type       string
	Category   string
	Attributes []string
	Origin     string
	Folder     string
	SourcePath string
}

// Options configures a generator run.
type Options struct {
	DatamineRoot   string // path to the dcs-lua-datamine repo root
	OutDir         string // where framework/units.lua + statics.lua are written
	Now            string // injected for test determinism; production: leave empty
	DatamineCommit string // optional git SHA for the header banner
}

// Run executes the full pipeline. Returns the count of entries written to
// units.lua, statics.lua, and any error. Skipped entries (zero Bucket from
// Classify) are not counted. Errors include unwritable output paths and any
// I/O error from parsing.
func Run(opts Options) (units, statics int, err error) {
	if opts.DatamineRoot == "" {
		return 0, 0, fmt.Errorf("genunits: DatamineRoot is required")
	}
	if opts.OutDir == "" {
		return 0, 0, fmt.Errorf("genunits: OutDir is required")
	}
	now := opts.Now
	if now == "" {
		now = time.Now().UTC().Format(time.RFC3339)
	}

	entries, err := Walk(opts.DatamineRoot)
	if err != nil {
		return 0, 0, fmt.Errorf("genunits: walk: %w", err)
	}

	// Classify each entry. Skip zero-bucket (e.g. GT_t/) entries.
	type pending struct {
		entry  Entry
		bucket Bucket
	}
	var keep []pending
	for _, e := range entries {
		b := Classify(e)
		if b.IsZero() {
			continue
		}
		keep = append(keep, pending{entry: e, bucket: b})
	}

	// Resolve identifiers with collision handling. We sanitize within each
	// (Top, Cat, Sub) bucket independently — a "T_72B" tank and a
	// hypothetical "T-72B" something-else in another bucket can coexist.
	bucketKey := func(b Bucket) string { return b.Top + "/" + b.Cat + "/" + b.Sub }
	byBucket := map[string][]string{}
	bucketIndex := map[string]Bucket{}
	for _, p := range keep {
		k := bucketKey(p.bucket)
		byBucket[k] = append(byBucket[k], p.entry.Type)
		bucketIndex[k] = p.bucket
	}
	identByTypeInBucket := map[string]map[string]string{}
	for k, types := range byBucket {
		sort.Strings(types)
		identByTypeInBucket[k] = ResolveCollisions(types)
	}

	// Build the ClassifiedEntry slice for the emitter.
	var classified []ClassifiedEntry
	for _, p := range keep {
		k := bucketKey(p.bucket)
		ident := identByTypeInBucket[k][p.entry.Type]
		classified = append(classified, ClassifiedEntry{
			Bucket:      p.bucket,
			Type:        p.entry.Type,
			Identifier:  ident,
			OriginLabel: OriginLabel(p.entry.Origin),
		})
	}

	// Count + emit.
	for _, c := range classified {
		switch c.Bucket.Top {
		case "units":
			units++
		case "statics":
			statics++
		}
	}

	if err := writeFile(filepath.Join(opts.OutDir, "units.lua"), func(w *os.File) error {
		return EmitUnits(w, classified, opts.DatamineCommit, now)
	}); err != nil {
		return 0, 0, fmt.Errorf("genunits: write units.lua: %w", err)
	}
	if err := writeFile(filepath.Join(opts.OutDir, "statics.lua"), func(w *os.File) error {
		return EmitStatics(w, classified, opts.DatamineCommit, now)
	}); err != nil {
		return 0, 0, fmt.Errorf("genunits: write statics.lua: %w", err)
	}
	return units, statics, nil
}

// writeFile creates the file at path and invokes write to fill it. The file
// is closed before returning even if write returns an error.
func writeFile(path string, write func(*os.File) error) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	werr := write(f)
	cerr := f.Close()
	if werr != nil {
		return werr
	}
	return cerr
}
```

- [ ] **Step 2: Replace the stub test with an end-to-end Run test**

Replace `tools/internal/genunits/genunits_test.go` with:

```go
package genunits

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestEntryZeroValue(t *testing.T) {
	var e Entry
	if e.Type != "" || e.Category != "" || len(e.Attributes) != 0 || e.Origin != "" || e.Folder != "" {
		t.Errorf("expected zero Entry to have empty fields, got %+v", e)
	}
}

func TestRun_endToEnd(t *testing.T) {
	out := t.TempDir()
	u, s, err := Run(Options{
		DatamineRoot:   "testdata",
		OutDir:         out,
		Now:            "2026-04-30T00:00:00Z",
		DatamineCommit: "fakecommit",
	})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}

	// 4 group-spawnable units (F-16C_50, T-72B, Soldier M4, T-80B), 1 static (Bunker).
	if u != 4 {
		t.Errorf("units count: got %d, want 4", u)
	}
	if s != 1 {
		t.Errorf("statics count: got %d, want 1", s)
	}

	unitsBytes, err := os.ReadFile(filepath.Join(out, "units.lua"))
	if err != nil {
		t.Fatalf("read units.lua: %v", err)
	}
	units := string(unitsBytes)

	mustContain := []string{
		"AUTO-GENERATED",
		"dcs-lua-datamine @ fakecommit",
		"2026-04-30T00:00:00Z",
		`---@alias sms.GroupSpawnType`,
		`F_16C_50 = "F-16C_50"`,
		`T_72B = "T-72B"`,
		`Soldier_M4 = "Soldier M4"`,
		`T_80B = "T-80B"`,
		`-- Cold War Asset Pack`,
		`sms.units.origin_of = function`,
		`["T-80B"]`,
	}
	for _, want := range mustContain {
		if !strings.Contains(units, want) {
			t.Errorf("units.lua missing %q\n--- units.lua ---\n%s", want, units)
		}
	}

	staticsBytes, err := os.ReadFile(filepath.Join(out, "statics.lua"))
	if err != nil {
		t.Fatalf("read statics.lua: %v", err)
	}
	statics := string(staticsBytes)
	for _, want := range []string{
		`---@alias sms.StaticSpawnType`,
		`Bunker = "Bunker"`,
		`sms.statics.fortifications = {`,
		`sms.statics.origin_of = function`,
	} {
		if !strings.Contains(statics, want) {
			t.Errorf("statics.lua missing %q", want)
		}
	}
}
```

- [ ] **Step 3: Run tests to verify they pass**

Run from `tools/`:
```
go test ./internal/genunits/...
```
Expected: ALL PASS.

- [ ] **Step 4: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add tools/internal/genunits/genunits.go tools/internal/genunits/genunits_test.go
git commit -m "feat(genunits): wire the full parse→classify→sanitize→emit pipeline"
```

---

### Task 8: CLI sub-command

**Files:**
- Create: `tools/cmd/dcs-sms/genunits.go`
- Create: `tools/cmd/dcs-sms/genunits_test.go`
- Modify: `tools/cmd/dcs-sms/dispatch.go` (add the new command to the usage banner)

- [ ] **Step 1: Add the sub-command registration**

Create `tools/cmd/dcs-sms/genunits.go`:

```go
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/nielsvaes/dcs-sms/tools/internal/genunits"
)

func init() {
	register("gen-units", genUnitsCmd)
}

// genUnitsCmd runs the units/statics catalog generator. Exit codes:
//
//	0 — success; framework/units.lua + framework/statics.lua written.
//	1 — generator error (parse, emit, or validation failed).
//	2 — flag parse error or required path missing.
func genUnitsCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("gen-units", flag.ContinueOnError)
	fs.SetOutput(stderr)
	flagDatamine := fs.String("datamine", "", "path to dcs-lua-datamine repo (default: $DCS_LUA_DATAMINE_PATH or D:/git/dcs-lua-datamine)")
	flagOutDir := fs.String("out-dir", "", "where to write units.lua/statics.lua (default: ./framework relative to cwd)")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	datamine := *flagDatamine
	if datamine == "" {
		datamine = os.Getenv("DCS_LUA_DATAMINE_PATH")
	}
	if datamine == "" {
		datamine = "D:/git/dcs-lua-datamine"
	}

	outDir := *flagOutDir
	if outDir == "" {
		// Default: ./framework relative to cwd
		cwd, err := os.Getwd()
		if err != nil {
			fmt.Fprintln(stderr, "dcs-sms gen-units: cannot determine cwd:", err)
			return 2
		}
		outDir = filepath.Join(cwd, "framework")
	}

	if _, err := os.Stat(datamine); err != nil {
		fmt.Fprintln(stderr, "dcs-sms gen-units: datamine path not found:", datamine)
		return 2
	}
	if _, err := os.Stat(outDir); err != nil {
		fmt.Fprintln(stderr, "dcs-sms gen-units: out-dir not found:", outDir)
		return 2
	}

	u, s, err := genunits.Run(genunits.Options{
		DatamineRoot: datamine,
		OutDir:       outDir,
	})
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms gen-units:", err)
		return 1
	}
	fmt.Fprintf(stdout, "wrote %s/units.lua (%d entries) and %s/statics.lua (%d entries)\n", outDir, u, outDir, s)
	return 0
}
```

- [ ] **Step 2: Add the new command to the usage banner**

Open `tools/cmd/dcs-sms/dispatch.go` and update the `printUsage` block. Replace:

```go
	fmt.Fprintln(w, "  exec          execute a Lua snippet inside the running mission")
	fmt.Fprintln(w, "  status        report whether the hook is alive and a mission is loaded")
	fmt.Fprintln(w, "  tail-log      read recent lines from dcs.log")
	fmt.Fprintln(w, "  install-hook  install/update the Lua hook in Saved Games/DCS*/Scripts/Hooks/")
```

With:

```go
	fmt.Fprintln(w, "  exec          execute a Lua snippet inside the running mission")
	fmt.Fprintln(w, "  status        report whether the hook is alive and a mission is loaded")
	fmt.Fprintln(w, "  tail-log      read recent lines from dcs.log")
	fmt.Fprintln(w, "  install-hook  install/update the Lua hook in Saved Games/DCS*/Scripts/Hooks/")
	fmt.Fprintln(w, "  gen-units     regenerate framework/units.lua + statics.lua from dcs-lua-datamine")
```

- [ ] **Step 3: Write a sub-command dispatch test**

Create `tools/cmd/dcs-sms/genunits_test.go`:

```go
package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestGenUnitsCmd_unknownDatamine(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := dispatch([]string{"gen-units", "--datamine", "/no/such/path"}, &stdout, &stderr)
	if code != 2 {
		t.Errorf("expected exit 2 for missing datamine, got %d", code)
	}
	if !strings.Contains(stderr.String(), "datamine path not found") {
		t.Errorf("stderr missing 'datamine path not found': %s", stderr.String())
	}
}

func TestGenUnitsCmd_helpFlagDoesNotCrash(t *testing.T) {
	var stdout, stderr bytes.Buffer
	// `--help` causes flag.ContinueOnError to print usage and return ErrHelp;
	// our code should exit 2 and print to stderr, not panic.
	code := dispatch([]string{"gen-units", "--help"}, &stdout, &stderr)
	if code != 2 {
		t.Errorf("expected exit 2 for --help, got %d", code)
	}
}

func TestGenUnitsCmd_appearsInUsage(t *testing.T) {
	var stdout, stderr bytes.Buffer
	dispatch([]string{"--help"}, &stdout, &stderr)
	if !strings.Contains(stdout.String(), "gen-units") {
		t.Errorf("--help output missing gen-units listing: %s", stdout.String())
	}
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run from `tools/`:
```
go test ./cmd/dcs-sms/... -run "TestGenUnits"
```
Expected: PASS.

Also run the broader test suite to ensure no regressions:
```
go test ./...
```
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add tools/cmd/dcs-sms/genunits.go tools/cmd/dcs-sms/genunits_test.go tools/cmd/dcs-sms/dispatch.go
git commit -m "feat(cli): add dcs-sms gen-units sub-command"
```

---

### Task 9: Run the generator, validate, commit framework files

**Files:**
- Create: `framework/units.lua` (generator output, ~1500 lines)
- Create: `framework/statics.lua` (generator output, ~800 lines)

- [ ] **Step 1: Build and run the generator**

From `tools/`:
```
go run ./cmd/dcs-sms gen-units --datamine D:/git/dcs-lua-datamine --out-dir ../framework
```

Expected output (counts approximate):
```
wrote ../framework/units.lua (~1500 entries) and ../framework/statics.lua (~700 entries)
```

If the run errors or counts are way off (e.g. 0 entries), inspect stderr and re-check the parser regex against any specific file that surfaces.

- [ ] **Step 2: Sanity-check the generated files**

Run from the worktree root:
```
head -20 framework/units.lua
head -20 framework/statics.lua
```

Expected: both start with the AUTO-GENERATED banner, the LuaCATS alias, and the `assert(type(sms) == "table", ...)` line.

```
grep -c "^  [A-Za-z_]" framework/units.lua
```

Should be in the ballpark of 1500 (one identifier per line in the table bodies).

- [ ] **Step 3: Verify Lua syntax**

The mission environment doesn't have `luac` available natively on Windows, but if the user has Lua installed, use it:

```
luac -p framework/units.lua && luac -p framework/statics.lua && echo "OK"
```

If `luac` is not on PATH, skip this step — the smoke test in Task 12 covers actual load-in-DCS validation.

- [ ] **Step 4: Spot-check a few well-known entries**

Run from the worktree root:
```
grep -E '^\s+F_16C_50 = "F-16C_50",' framework/units.lua
grep -E '^\s+T_72B = "T-72B",' framework/units.lua
grep -E '^\s+T_80B = "T-80B",' framework/units.lua | grep "Cold War"
grep -E '^\s+Bunker = "Bunker",' framework/statics.lua
```

Expected: each grep returns one matching line.

- [ ] **Step 5: Commit the generated files**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add framework/units.lua framework/statics.lua
git commit -m "feat(framework): add generated units and statics catalogs

Generated by `dcs-sms gen-units` from dcs-lua-datamine.
This commit adds the catalog tables (sms.units.*, sms.statics.*),
LuaCATS aliases, and origin_of helpers."
```

---

### Task 10: Update `framework/load_all.lua`

**Files:**
- Modify: `framework/load_all.lua`

- [ ] **Step 1: Add `units.lua` and `statics.lua` to the load chain**

Open `framework/load_all.lua`. Locate the `modules` table:

```lua
local modules = {
  "sms.lua",
  "log.lua",
  "utils.lua",
  "targets.lua",
  ...
}
```

Insert `units.lua` and `statics.lua` between `utils.lua` and `targets.lua`:

```lua
local modules = {
  "sms.lua",
  "log.lua",
  "utils.lua",
  "units.lua",
  "statics.lua",
  "targets.lua",
  "designations.lua",
  "group.lua",
  "unit.lua",
  "area.lua",
  "timer.lua",
  "group_spawn.lua",
  "static.lua",
  "events.lua",
  "weapon.lua",
  "task.lua",
  "commands.lua",
  "options.lua",
}
```

- [ ] **Step 2: Verify the file still parses**

```
luac -p framework/load_all.lua && echo "OK"
```

If `luac` is unavailable, skip — Task 12's smoke test confirms the chain loads.

- [ ] **Step 3: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add framework/load_all.lua
git commit -m "feat(framework): load units.lua and statics.lua via load_all"
```

---

### Task 11: Update `group_spawn.lua` and `static.lua` LuaCATS annotations

**Files:**
- Modify: `framework/group_spawn.lua`
- Modify: `framework/static.lua`

- [ ] **Step 1: Inspect existing annotations**

Run:
```
grep -n "type" framework/group_spawn.lua | grep -E "^\s*---@(field|param)" | head
grep -n "type" framework/static.lua | grep -E "^\s*---@(field|param)" | head
```

Expected: at least one `---@field type string` (or similar) line per file. Note the line numbers — that's where the annotation update lands.

- [ ] **Step 2: Replace `string` with the alias on the `type` field**

In `framework/group_spawn.lua`, find every LuaCATS field annotation that documents the `type` field of the spawn config (typically a class declaration like `---@class sms.group.SpawnUnit`). Change:

```lua
---@field type string  DCS unit type name
```

to:

```lua
---@field type sms.GroupSpawnType  DCS unit type name (autocompleted via sms.units.*)
```

In `framework/static.lua`, do the same for the static spawn config's `type` field:

```lua
---@field type sms.StaticSpawnType  DCS static type name (autocompleted via sms.statics.*)
```

If the annotations don't exist in the expected places, add them. Use the existing `---@class` declarations in those files as the anchor point.

- [ ] **Step 3: Verify the files still parse**

```
luac -p framework/group_spawn.lua && luac -p framework/static.lua && echo "OK"
```

If `luac` is unavailable, skip — Task 12's smoke test confirms the framework loads.

- [ ] **Step 4: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add framework/group_spawn.lua framework/static.lua
git commit -m "feat(framework): annotate spawn config type fields with new aliases"
```

---

### Task 12: Framework smoke test

**Files:**
- Create: `framework/test/smoke_units.sh`

- [ ] **Step 1: Create the smoke test**

Create `framework/test/smoke_units.sh`:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for sms.units and sms.statics catalogs.
# Verifies the catalogs load cleanly and resolve a representative subset
# of well-known type strings, plus origin_of behavior for base / pack /
# unknown / non-string inputs.
#
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.
# (No spawning is performed — this is a pure-string-equality smoke.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

cd "${FRAMEWORK_DIR}"

# Helpers
expect_eq_string() {
  local label="$1"
  local code="$2"
  local expected="$3"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":\"${expected}\"" \
    || { echo "FAIL: ${label} (expected ${expected}): ${result}"; exit 1; }
  echo "PASS: ${label}"
}

expect_nil() {
  local label="$1"
  local code="$2"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":null' \
    || { echo "FAIL: ${label} (expected null): ${result}"; exit 1; }
  echo "PASS: ${label}"
}

# Reload the framework once so we know we're testing the just-built version.
"${DCSSMS}" exec --file load_all.lua >/dev/null

# Spot-checks for sms.units across each top-level bucket.
expect_eq_string "planes.F_16C_50"        "return sms.units.planes.F_16C_50"             "F-16C_50"
expect_eq_string "helicopters.AH_64D"     "return sms.units.helicopters.AH_64D"          "AH-64D"
expect_eq_string "armor.tanks.T_72B"      "return sms.units.armor.tanks.T_72B"           "T-72B"
expect_eq_string "armor.ifv.BMP_2"        "return sms.units.armor.ifv.BMP_2"             "BMP-2"
expect_eq_string "armor.apc.BTR_80"       "return sms.units.armor.apc.BTR_80"            "BTR-80"
expect_eq_string "artillery.M_109"        "return sms.units.artillery.M_109"             "M-109"
expect_eq_string "infantry.Soldier_M4"    "return sms.units.infantry.Soldier_M4"         "Soldier M4"
expect_eq_string "ships.warships.MOSCOW"  "return sms.units.ships.warships.MOSCOW"       "MOSCOW"

# sms.statics
expect_eq_string "fortifications.Bunker" "return sms.statics.fortifications.Bunker"      "Bunker"
expect_eq_string "animals.Cow"           "return sms.statics.animals.Cow"                "Cow"

# origin_of: base game
expect_nil "origin_of base F-16C_50"     "return sms.units.origin_of('F-16C_50')"

# origin_of: asset pack (Cold War — T-80B is a CWAP tank)
expect_eq_string "origin_of T-80B"       "return sms.units.origin_of('T-80B')"          "Cold War Asset Pack"

# origin_of: unknown / non-string (silent nil)
expect_nil "origin_of unknown"           "return sms.units.origin_of('definitely-not-a-type')"
expect_nil "origin_of nil"               "return sms.units.origin_of(nil)"
expect_nil "origin_of number"            "return sms.units.origin_of(42)"

echo
echo "ALL smoke_units checks passed."
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x framework/test/smoke_units.sh
```

(Note: on Windows under git-bash, `chmod` is a no-op for permission bits but git records the `+x` mode flag.)

- [ ] **Step 3: Verify the script syntax**

```
bash -n framework/test/smoke_units.sh && echo "OK"
```

Expected: `OK`. (Actually running the smoke requires DCS — that's the user's job in /bring-it-home territory.)

- [ ] **Step 4: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add framework/test/smoke_units.sh
git commit -m "test(framework): add smoke_units.sh for catalog load + origin_of"
```

---

### Task 13: API documentation

**Files:**
- Create: `docs/api/units.md`
- Create: `docs/api/statics.md`

- [ ] **Step 1: Write `docs/api/units.md`**

Create `docs/api/units.md`:

```markdown
# `sms.units` — catalog of every group-spawnable DCS type

`sms.units` is a generated catalog of every DCS unit type that can be spawned via [`sms.group.create`](group.md) or vanilla `coalition.addGroup`. Each entry is a string constant — assign it to the `type` field of a spawn config and DCS does the rest.

This page is the canonical reference for `sms.units`. The cross-cutting framework rules every API call follows live in [`AGENTS.md`](../../AGENTS.md). The catalog itself is generated by `dcs-sms gen-units` from [dcs-lua-datamine](https://github.com/mrSkortch/DCS-miscScripts/tree/master/dcs-lua-datamine) — do not hand-edit `framework/units.lua`.

## Categories

The catalog is organized into one or two-level sub-namespaces. Two levels are used only where DCS itself differentiates in a way mission code cares about (tanks vs IFVs vs APCs; SAMs vs AAA vs radars vs MANPADS; warships vs carriers vs subs vs civilian).

| Namespace | Contains | Example |
|---|---|---|
| `sms.units.planes` | All fixed-wing aircraft | `sms.units.planes.F_16C_50 → "F-16C_50"` |
| `sms.units.helicopters` | All rotary-wing aircraft | `sms.units.helicopters.AH_64D → "AH-64D"` |
| `sms.units.armor.tanks` | Main battle tanks | `sms.units.armor.tanks.T_72B → "T-72B"` |
| `sms.units.armor.ifv` | Infantry fighting vehicles | `sms.units.armor.ifv.BMP_2 → "BMP-2"` |
| `sms.units.armor.apc` | Armored personnel carriers | `sms.units.armor.apc.BTR_80 → "BTR-80"` |
| `sms.units.armor.misc` | Other armored units | — |
| `sms.units.air_defence.sam` | Surface-to-air missile launchers + SAM radars | `sms.units.air_defence.sam.S_300PS_5P85C_ln → "S-300PS 5P85C ln"` |
| `sms.units.air_defence.aaa` | Anti-aircraft artillery | `sms.units.air_defence.aaa.ZSU_23_4_Shilka → "ZSU-23-4 Shilka"` |
| `sms.units.air_defence.radar` | Standalone radars (EWR) | `sms.units.air_defence.radar._1L13_EWR → "1L13 EWR"` |
| `sms.units.air_defence.manpads` | Shoulder-launched SAMs | `sms.units.air_defence.manpads.Stinger_comm → "Stinger comm"` |
| `sms.units.air_defence.misc` | Command vehicles, generators | — |
| `sms.units.artillery` | Howitzers, MLRS, mortars | `sms.units.artillery.M_109 → "M-109"` |
| `sms.units.infantry` | Soldiers | `sms.units.infantry.Soldier_M4 → "Soldier M4"` |
| `sms.units.unarmed` | Trucks, jeeps, fuel, supply | `sms.units.unarmed.Hummer → "Hummer"` |
| `sms.units.missiles` | Surface-to-surface missile launchers | `sms.units.missiles.Scud_B → "Scud_B"` |
| `sms.units.ships.warships` | Frigates, destroyers, cruisers, missile boats | `sms.units.ships.warships.MOSCOW → "MOSCOW"` |
| `sms.units.ships.carriers` | Aircraft carriers | `sms.units.ships.carriers.CVN_71 → "CVN_71"` |
| `sms.units.ships.civilian` | Cargo vessels, tugs, fishing boats | `sms.units.ships.civilian.HandyWind → "HandyWind"` |
| `sms.units.ships.submarines` | Subs | `sms.units.ships.submarines.KILO → "KILO"` |
| `sms.units.trains` | Locomotives + cars | `sms.units.trains.Locomotive → "Locomotive"` |

## Identifier sanitization

DCS type-strings include hyphens, dots, spaces, slashes, even quotation marks — none of which are legal in a Lua identifier. The generator sanitizes the original DCS string into a Lua-safe identifier on the left-hand side of the assignment; the right-hand side is the verbatim DCS string passed to the spawn API:

| DCS string | Lua identifier |
|---|---|
| `F-16C_50` | `F_16C_50` |
| `Bf 109 K-4` | `Bf_109_K_4` |
| `AV-8B N/A` | `AV_8B_N_A` |
| `2B11 mortar` | `_2B11_mortar` (leading-digit prefix) |

Sanitization rules:
1. Every non-`[A-Za-z0-9_]` character becomes `_`.
2. Runs of `_` collapse to a single `_`.
3. If the first character is a digit, prefix `_`.

## Asset-pack origins

Entries from non-base content are tagged with a one-line trailing comment naming the asset pack. Mission authors writing a call site never see this — autocomplete just works. When *reading* a finished mission, grepping for `-- Cold War Asset Pack` or `-- WWII Assets` surfaces dependencies.

```lua
sms.units.armor.tanks.T_72B    = "T-72B"
sms.units.armor.tanks.T_55     = "T-55"          -- Cold War Asset Pack
sms.units.armor.tanks.T_34_85  = "T-34-85"       -- WWII Assets
```

The `--` comment is informational only — Lua treats the assignment exactly as if the comment weren't there.

## `sms.units.origin_of(type_string)`

**Synopsis** — given a DCS type-string, return the asset-pack name if the type belongs to one, or `nil` for base game / unknown strings.

```lua
sms.units.origin_of("T-80B")            --> "Cold War Asset Pack"
sms.units.origin_of("CVN_71")           --> "Supercarrier"
sms.units.origin_of("F-16C_50")         --> nil  (base game)
sms.units.origin_of("Type-not-a-thing") --> nil  (unknown)
sms.units.origin_of(nil)                --> nil  (silent on non-string)
sms.units.origin_of(42)                 --> nil  (silent on non-string)
```

**Failure model** — silent-nil. Non-string input or unrecognized type returns `nil` without logging — "is this a known asset-pack type?" is a normal yes/no question, not API misuse.

**Use case — gating mission features on installed packs:**

```lua
local function require_pack(unit_type, friendly_name)
  local pack = sms.units.origin_of(unit_type)
  if pack and not g_user_owned_packs[pack] then
    sms.log.warn(friendly_name .. " requires " .. pack .. " — falling back")
    return false
  end
  return true
end
```

## Use at the call site

```lua
sms.group.create({
  name     = "tank-section",
  type     = sms.units.armor.tanks.T_72B,        -- autocomplete shows every tank
  position = {x = 0, y = 0, z = 0},
  country  = "USA",
})

sms.group.create({
  name     = "f18-cap",
  type     = sms.units.planes.FA_18C_hornet,     -- raw string also works:
                                                 --   type = "FA-18C_hornet"
                                                 -- LuaCATS sms.GroupSpawnType
                                                 -- alias catches typos either way.
  position = airfield_pos,
  country  = "USA",
  category = "airplane",
  units    = { { alt = 6000, heading = 90 } },
})
```

## Regenerating the catalog

After a DCS update the catalog can be re-emitted from a fresh dcs-lua-datamine pull:

```
dcs-sms gen-units --datamine /path/to/dcs-lua-datamine
```

Defaults: datamine path falls back to `$DCS_LUA_DATAMINE_PATH` then `D:/git/dcs-lua-datamine`; out-dir defaults to `./framework/` relative to cwd. The command overwrites `framework/units.lua` and `framework/statics.lua` — review the diff before committing.

## See also

- [`sms.group`](group.md) — spawn factories that consume these type strings.
- [`sms.statics`](statics.md) — sibling catalog for static-spawnable objects.
- [Spec: 2026-04-30-units-statics-catalog](../superpowers/specs/2026-04-30-units-statics-catalog.md) — design rationale.
```

- [ ] **Step 2: Write `docs/api/statics.md`**

Create `docs/api/statics.md`:

```markdown
# `sms.statics` — catalog of every static-spawnable DCS type

`sms.statics` is a generated catalog of every DCS static-object type that can be spawned via [`sms.static.create`](static.md) or vanilla `coalition.addStaticObject`. Sibling of [`sms.units`](units.md); same shape, different spawn API. Each entry is a string constant.

This page is the canonical reference for `sms.statics`. The cross-cutting framework rules every API call follows live in [`AGENTS.md`](../../AGENTS.md). The catalog itself is generated by `dcs-sms gen-units` from dcs-lua-datamine — do not hand-edit `framework/statics.lua`.

## Categories

| Namespace | Contains | Example |
|---|---|---|
| `sms.statics.fortifications` | Bunkers, walls, towers, sandbags | `sms.statics.fortifications.Bunker → "Bunker"` |
| `sms.statics.cargos` | Slingable crates and containers | `sms.statics.cargos.container_20ft → "container_20ft"` |
| `sms.statics.personnel` | Deck crew, statue-soldiers | `sms.statics.personnel.us_carrier_tech → "us carrier tech"` |
| `sms.statics.heliports` | FARPs, helipads, oil rigs | `sms.statics.heliports.FARP → "FARP"` |
| `sms.statics.warehouses` | Warehouse buildings | — |
| `sms.statics.airfields` | Grass strips | `sms.statics.airfields.GrassAirfield → "GrassAirfield"` |
| `sms.statics.equipment` | Aircraft deck equipment, jet starters, generators | — |
| `sms.statics.effects` | Smoke, fire, markers | `sms.statics.effects.big_smoke → "big_smoke"` |
| `sms.statics.animals` | Cows, etc. | `sms.statics.animals.Cow → "Cow"` |
| `sms.statics.airships` | LTA vehicles (balloons) | — |
| `sms.statics.ground_objects` | Misc | — |

Identifier sanitization, asset-pack origin tagging, and `sms.statics.origin_of` all work the same way as in [`sms.units`](units.md). See that page for details.

## Use at the call site

```lua
sms.static.create({
  name     = "fuel-tank",
  type     = sms.statics.fortifications.FARP_Fuel_Depot,
  position = {x = 0, y = 0, z = 0},
  country  = "USA",
  heading  = 45,
})
```

## See also

- [`sms.static`](static.md) — spawn factory that consumes these type strings.
- [`sms.units`](units.md) — sibling catalog for group-spawnable objects.
- [Spec: 2026-04-30-units-statics-catalog](../superpowers/specs/2026-04-30-units-statics-catalog.md) — design rationale.
```

- [ ] **Step 3: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add docs/api/units.md docs/api/statics.md
git commit -m "docs(api): add reference pages for sms.units and sms.statics"
```

---

### Task 14: Update AGENTS.md §7 module index

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Add two rows to the §7 module index**

Open `AGENTS.md`. Locate §7 — the module index table. After the `sms.utils` row, insert two new rows:

```markdown
| `sms.units` | `units.lua` | [`docs/api/units.md`](docs/api/units.md) | Generated catalog of every group-spawnable DCS type, organized by category; includes `origin_of` for asset-pack lookup. |
| `sms.statics` | `statics.lua` | [`docs/api/statics.md`](docs/api/statics.md) | Generated catalog of every static-spawnable DCS type, parallel to `sms.units`. |
```

The full §7 table after the edit should have these rows in this order: sms (root), sms.log, sms.utils, **sms.units**, **sms.statics**, sms.targets, sms.designations, sms.group, sms.unit, sms.area, sms.timer, sms.static, sms.events, sms.weapon, sms.task, sms.commands, sms.options.

- [ ] **Step 2: Verify the table is well-formed**

```
grep -n "^|" AGENTS.md | head -25
```

Expected: pipe-delimited rows render as a continuous table; no truncated columns.

- [ ] **Step 3: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/units-statics-catalog
git add AGENTS.md
git commit -m "docs(framework): add sms.units and sms.statics to AGENTS.md module index"
```

---

## Done

After Task 14 the worktree contains:

- A complete generator (`tools/internal/genunits/`) with unit tests.
- A new `dcs-sms gen-units` sub-command.
- Generated `framework/units.lua` and `framework/statics.lua` covering every spawnable DCS type, with LuaCATS aliases and `origin_of` helpers.
- Updated `framework/load_all.lua` so the catalogs are part of the standard load chain.
- LuaCATS annotations on `group_spawn.lua` and `static.lua` so raw string literals get typo-checking too.
- A smoke test covering catalog load + `origin_of` semantics.
- Reference docs at `docs/api/units.md` and `docs/api/statics.md`.
- Updated `AGENTS.md` §7 module index.

The user runs the smoke test against a live DCS mission, then `/bring-it-home` to merge.
