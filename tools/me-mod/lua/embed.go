// Package memod exposes the dcs_sms_me/* Lua source as an embed.FS so the
// install-me-mod subcommand can write the files into the user's DCS
// MissionEditor/modules directory. We need this thin wrapper because Go's
// //go:embed directive can only reference files in the same package
// directory or below — keeping the canonical mod source under
// tools/me-mod/lua/ means we also need a Go file here to embed it.
package memod

import "embed"

//go:embed dcs_sms_me
var FS embed.FS

// ModuleDirName is the on-disk subdirectory the install command writes
// into, under <DCS install>/MissionEditor/modules/.
const ModuleDirName = "dcs_sms_me"

// RequireLine is the Lua snippet appended to <DCS install>/MissionEditor/MissionEditor.lua
// to load the mod. Sentinel comments delimit it so install/uninstall can
// detect and remove the patch surgically.
const (
	RequireBeginMarker = "-- dcs-sms-me-mod begin"
	RequireEndMarker   = "-- dcs-sms-me-mod end"
	RequireBody        = "require('dcs_sms_me')"
)

// PatchBlock is the full block appended to MissionEditor.lua at install time.
const PatchBlock = "\n" + RequireBeginMarker + "\n" + RequireBody + "\n" + RequireEndMarker + "\n"
