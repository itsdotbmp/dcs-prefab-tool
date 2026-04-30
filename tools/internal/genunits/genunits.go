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

	// Track unrecognized folders so we can warn once per folder rather than
	// per-entry (a future DCS folder we haven't classified would otherwise
	// produce hundreds of identical warnings).
	unknownFolders := map[string]int{}
	knownSkippedFolders := map[string]bool{
		"GT_t": true, // explicit per spec D8 / classify.go
	}

	// Classify each entry. Skip zero-bucket entries; track unknown-folder
	// occurrences for the post-walk warning.
	type pending struct {
		entry  Entry
		bucket Bucket
	}
	var keep []pending
	for _, e := range entries {
		b := Classify(e)
		if b.IsZero() {
			if !knownSkippedFolders[e.Folder] {
				unknownFolders[e.Folder]++
			}
			continue
		}
		keep = append(keep, pending{entry: e, bucket: b})
	}

	// Warn about unrecognized folders. Sort for deterministic output.
	if len(unknownFolders) > 0 {
		names := make([]string, 0, len(unknownFolders))
		for name := range unknownFolders {
			names = append(names, name)
		}
		sort.Strings(names)
		for _, name := range names {
			fmt.Fprintf(os.Stderr,
				"genunits: warning: skipped %d entries from unrecognized folder %q "+
					"(add a Classify case for it in classify.go)\n",
				unknownFolders[name], name)
		}
	}

	// Resolve identifiers with collision handling. We sanitize within each
	// (Top, Cat, Sub) bucket independently — a "T_72B" tank and a
	// hypothetical "T-72B" something-else in another bucket can coexist.
	bucketKey := func(b Bucket) string { return b.Top + "/" + b.Cat + "/" + b.Sub }
	byBucket := map[string][]string{}
	for _, p := range keep {
		k := bucketKey(p.bucket)
		byBucket[k] = append(byBucket[k], p.entry.Type)
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
