-- dcs-sms logger module. Attaches sms.log with info/error functions and
-- a per-module logger factory.
--
-- Top-level sms.log.info / sms.log.error are untagged callers (prefix [sms]).
-- sms.log.module(name?) returns a tagged logger whose calls prefix every
-- line with [<tag>]. When `name` is omitted the tag is auto-derived from
-- the caller's file path:
--   debug.getinfo(2, "S").source  ->  "@.../framework/utils.lua"
--   strip leading "@", take basename, strip ".lua"           ->  "utils"
--   prepend "sms."                                            ->  "sms.utils"
-- When `name` is provided it is used verbatim (no automatic "sms." prefix).
-- If auto-derivation fails (caller is a chunk loaded via the bridge,
-- source is "[string \"...\"]") the tag falls back to "sms.unknown".

assert(sms, "framework/sms.lua must be loaded first")
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
    info  = function(msg) env.info ("[" .. tag .. "] " .. tostring(msg)) end,
    error = function(msg) env.error("[" .. tag .. "] " .. tostring(msg)) end,
  }
end

-- TODO future: debug/warn levels + sms.log.set_level("info") for runtime
-- filtering. End-state is four levels (debug/info/warn/error) with a
-- threshold that mutes anything below it. Not in v1.
