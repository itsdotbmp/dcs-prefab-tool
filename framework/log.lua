-- dcs-sms logger module. Attaches sms.log with info/error functions and
-- a per-module logger factory.
--
-- Top-level sms.log.info / sms.log.error are untagged callers (prefix [sms]).
-- sms.log.module(name?) returns a tagged logger whose calls prefix every
-- line with [<tag>]. When `name` is provided it is used verbatim (no
-- automatic "sms." prefix) — caller is in full control.
--
-- Auto-derivation (when `name` is omitted) reads the caller's chunk source
-- via debug.getinfo(2, "S").source and pulls the basename:
--   "@.../framework/utils.lua"  ->  "utils"  ->  "sms.utils"
--
-- This works for files loaded via dofile()/loadfile() (mechanisms A and C
-- in the framework's load story). It does NOT work for chunks loaded via
-- the bridge (mechanism D, v1's only load path) — net.dostring_in does
-- not set a chunkname, so info.source is the wrapper source string itself
-- and the .lua$ pattern doesn't match. Bridge-loaded modules must pass
-- the tag explicitly. See framework/utils.lua for the v1 pattern.
-- Auto-derivation falls back to "sms.unknown" when no .lua basename is
-- recoverable.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
sms.log = sms.log or {}

sms.log.info  = function(msg) env.info ("[sms] " .. tostring(msg)) end
sms.log.error = function(msg) env.error("[sms] " .. tostring(msg)) end

sms.log.module = function(name)
  local tag = name
  if not tag then
    local info = debug.getinfo(2, "S")
    local src = info and info.source or ""
    local base = src:match("([^/\\]+)%.lua$")
    tag = base and ("sms." .. base) or "sms.unknown"
  end
  return {
    tag   = tag,
    info  = function(msg) env.info ("[" .. tag .. "] " .. tostring(msg)) end,
    error = function(msg) env.error("[" .. tag .. "] " .. tostring(msg)) end,
  }
end

-- TODO future: debug/warn levels + sms.log.set_level("info") for runtime
-- filtering. End-state is four levels (debug/info/warn/error) with a
-- threshold that mutes anything below it. Not in v1.
