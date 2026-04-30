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
