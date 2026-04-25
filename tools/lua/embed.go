// Package hook exposes the in-DCS Lua hook source (dcs-sms-hook.lua) as a
// byte slice for the install-hook subcommand to write into
// Saved Games/DCS*/Scripts/Hooks/. We need this thin wrapper because Go's
// //go:embed directive cannot reference files outside its own package
// directory — keeping the canonical hook source under tools/lua/ means we
// also need a Go file in tools/lua/ to embed it.
package hook

import _ "embed"

//go:embed dcs-sms-hook.lua
var Source []byte
