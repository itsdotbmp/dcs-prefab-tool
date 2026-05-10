# CLI reference autogeneration + README nav bar

GitHub issue: [#49](https://github.com/nielsvaes/dcs-sms/issues/49)

## Goal

Make the `dcs-sms` CLI surface browseable as a static reference site under
`docs/cli/`, generated from the binary itself. Add a top-level navigation bar
to `README.md` so users land on the repo and can immediately jump to
Framework / CLI / ME-mod / Changelog / Contributing / License.

## User value

Today the only way to discover what `dcs-sms` can do is to run
`dcs-sms <cmd> --help` one command at a time. There are ~90 commands across
the top-level + `me <noun> <verb>` namespaces. A user who's just learning the
CLI has nowhere to skim.

After this work:

- Open `docs/cli/README.md`, see every command grouped by namespace, click
  through to a per-command page with full flag table.
- Open the top-level `README.md`, see a centered nav bar with one click each
  to Framework / CLI / ME-mod docs.
- A new `dcs-sms doc` subcommand regenerates the reference pages from the
  binary, so docs cannot drift from flag definitions.

## Scope

### In scope

1. **Registry refactor.** Change `register(name, fn)` and
   `registerMe(noun, verb, fn)` to accept a `cmdInfo` struct that carries the
   run handler **plus** a flags-builder function and one-line synopsis text.
   Update every command site (~90 files) accordingly.
2. **Per-command file refactor.** Split each command into a pure
   `<cmd>Flags() (*flag.FlagSet, *<cmd>Opts)` builder + a thin run path that
   parses and dispatches. The build must remain green at every commit.
3. **`dcs-sms doc` subcommand.** New top-level command that walks both
   registries, builds each FlagSet via the flags-fn, calls
   `fs.VisitAll(...)`, and writes:
   - `docs/cli/README.md` — index with grouped tables.
   - `docs/cli/<cmd>.md` — one file per command (e.g.
     `docs/cli/exec.md`, `docs/cli/me-zone-create.md`).
4. **Generated content.** Run the generator and commit the output. ~90+1
   markdown files.
5. **Top-level `README.md` nav.** Add a `<p align="center">`
   `·`-separated nav paragraph between the existing Components section and
   the badges, matching the layout the user picked from psmux.

### Out of scope

- **Examples field.** Each command will have an `Examples []string` slot in
  its `cmdInfo` for future use, but populating it for every command is
  deferred. The doc generator must render examples when present and silently
  omit the section when not.
- **CI staleness check.** No make target that fails CI when `docs/cli/` is
  out of date. Generated output is committed; future drift is a follow-up
  concern.
- **Lua surface.** No edits to `tools/me-mod/lua/...` — verbs.lua agent is
  working there in parallel.
- **Auto-regen on every build.** Generation is on-demand via `dcs-sms doc`.
- **Hidden / internal commands.** Commands without a `Synopsis` set are
  treated as internal and skipped by the doc generator. (Useful for `doc`
  itself optionally — but in practice we'll document `doc` too.)

## Constraints

- **Branch:** work on `feat/me-execution-bridge` in
  `.worktrees/me-bridge/`. The verbs.lua agent has uncommitted changes in
  `tools/me-mod/lua/dcs_sms_me/verbs.lua`; do not touch any Lua file.
- **No regressions.** Every existing CLI test must still pass. `--help` for
  each command must still print equivalent output.
- **Atomic refactor commits.** The registry signature change and the
  dependent per-command refactors must land in a state where `go build
  ./...` and `go test ./...` are green. Pragmatically: a single "registry
  refactor + initial commands" commit, followed by per-namespace bulk
  commits.
- **Naming consistency.** Generated file slugs use `-` separators
  (`me-zone-create.md`, not `me_zone_create.md`) — matches existing
  `docs/api/<module>.md` style.

## Decisions

These were decided autonomously rather than asked of the user.

- **`cmdInfo` struct shape.** A single struct carries `Run`, `Flags`,
  `Synopsis`, and `Examples`. Reasoning: forces every register call to
  consider doc metadata at registration time; avoids a parallel doc-only
  registry that could drift from the run registry.
- **Synopsis is required for visible commands.** A `Synopsis: ""` flags the
  command as hidden from the doc generator. This lets us add invisible
  helper commands later without separate API.
- **Flags-builder returns `(*flag.FlagSet, *<cmd>Opts)`, not just the
  FlagSet.** Reasoning: the builder must build pointer-bound vars
  somewhere, and embedding them in a per-command opts struct is the
  cleanest Go idiom. The doc generator ignores the second return.
- **Output filenames.** Slug = command name with spaces replaced by `-`.
  Top-level: `exec.md`, `status.md`, … . Nested: `me-zone-create.md`,
  `me-trigger-add-action.md`, … .
- **Index page grouping.** Eight groups: top-level, then one per `me <noun>`
  (`me file`, `me group`, `me unit`, `me zone`, `me drawing`, `me trigger`).
  Generator infers the group from the first space-separated segments of the
  command name.
- **Per-command page sections.** In order: title, breadcrumb back to index,
  one-line synopsis, **Usage** code block, **Flags** table (Name | Type |
  Default | Description), **Examples** code blocks (if any), footer
  breadcrumb back to index. No frontmatter (markdown-only, GitHub-renderable
  with no extra tooling).
- **Default values in flags table.** Empty strings and zeros render as the
  literal `""` / `0` / `false` (matching `--help` output) so users see
  exactly what they'll get if they omit the flag.
- **Commands with sub-verbs (e.g. `me unit payload set/clear`) are
  handled by exposing each sub-verb as its own `cmdInfo` registered under a
  composed name like `me unit payload set`.** The current implementation
  has these as a single command that branches on argv[0]; we'll expand into
  one register call per sub-verb to keep the doc structure regular. If that
  proves too invasive for the parallelizable refactor, fall back to one
  composite page that lists all sub-verbs in a single page — record this
  fallback in plan task notes if it's taken.
- **README nav bar placement.** Between the existing badges block and the
  `DCS scripting framework, Mission Editor extension, and host-side
  tooling.` lead paragraph. Anchors used in the bar: `#components`,
  `docs/api/`, `docs/cli/`, `tools/me-mod/README.md`, `CHANGELOG.md`,
  `AGENTS.md`, `#licensing`.
- **No `internal/` package extraction yet.** The doc generator lives at
  `tools/cmd/dcs-sms/doc.go` next to its peers. If it grows, extract later.
- **`Type` column in flag table** uses Go's `flag.Flag.Value.String()`
  reflection to produce `string`, `int`, `float64`, `bool`,
  `time.Duration`. No special-casing of `flag.Value` interfaces beyond
  what the standard library exposes; the description text is the place
  for nuance.

## Open questions

None. All decisions above are recorded; if any prove wrong during
implementation, fix and amend the spec rather than pause.
