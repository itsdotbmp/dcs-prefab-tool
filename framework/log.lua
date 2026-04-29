-- dcs-sms logger module. Attaches sms.log with debug/info/warn/error
-- functions, a runtime-tunable level threshold, and a per-module logger
-- factory.
--
-- Levels (low to high): debug < info < warn < error. Calls below the
-- current threshold are dropped without touching env.*. Default
-- threshold is "info" — everything info-and-above visible.
--
-- Sinks:
--   debug, info  -> env.info     (DCS log line "INFO ...")
--   warn         -> env.warning  (DCS log line "WARNING ...")
--   error        -> env.error    (DCS log line "ERROR ...")
--
-- The framework convention after v1.1: `log.warn` for *caller misuse*
-- (bad arg type, missing field, named entity that doesn't exist, wrong
-- category for the verb), `log.error` for actual framework or DCS
-- failures (DCS rejected addGroup, internal invariants violated, user
-- callbacks raising under pcall). Negative-path smoke tests trigger
-- warns; unsurprising warns in dcs.log are not bugs.
--
-- Mute warns in production:
--   sms.log.set_level("error")
--
-- Top-level sms.log.<level> are untagged (prefix [sms]).
-- sms.log.module(name?) returns a tagged logger whose calls prefix
-- every line with [<tag>]. When `name` is provided it is used verbatim
-- (no automatic "sms." prefix) — caller is in full control.
--
-- Auto-derivation (when `name` is omitted) reads the caller's chunk
-- source via debug.getinfo(2, "S").source and pulls the basename:
--   "@.../framework/utils.lua"  ->  "utils"  ->  "sms.utils"
--
-- This works for files loaded via dofile()/loadfile(). It does NOT
-- work for chunks loaded via the bridge — net.dostring_in does not
-- set a chunkname, so info.source is the wrapper source string itself
-- and the .lua$ pattern doesn't match. Bridge-loaded modules must
-- pass the tag explicitly.
-- Auto-derivation falls back to "sms.unknown" when no .lua basename
-- is recoverable.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")

---@class sms.log
sms.log = sms.log or {}

---@class sms.log.module
---@field tag   string
---@field debug fun(msg: any)
---@field info  fun(msg: any)
---@field warn  fun(msg: any)
---@field error fun(msg: any)

local _LEVELS = { debug = 10, info = 20, warn = 30, error = 40 }
local _level = _LEVELS.info

-- Resolve a level name to its numeric weight; returns nil for unknown.
local function _resolve_level(name)
  if type(name) ~= "string" then return nil end
  return _LEVELS[name:lower()]
end

-- Pick the env.* sink for a level. Centralizes the level→DCS mapping
-- so module() and the top-level helpers stay in sync.
local function _sink_for(level_name)
  if level_name == "warn"  then return env.warning end
  if level_name == "error" then return env.error end
  return env.info  -- debug + info both go through env.info
end

-- Emit a tagged line at level_name. Skips silently if below threshold.
local function _emit(tag, level_name, msg)
  if _LEVELS[level_name] < _level then return end
  _sink_for(level_name)("[" .. tag .. "] " .. tostring(msg))
end

-- Set the runtime threshold. Accepts "debug" / "info" / "warn" / "error"
-- (case-insensitive). Anything below the threshold is dropped without
-- touching env.*. Logs an error and leaves the threshold unchanged on
-- bad input — the logger's own failure mode is still log + nil-ish.
---@param name "debug"|"info"|"warn"|"error"
sms.log.set_level = function(name)
  local n = _resolve_level(name)
  if not n then
    env.warning("[sms] log.set_level: unknown level '" .. tostring(name)
      .. "' (use debug/info/warn/error)")
    return
  end
  _level = n
end

-- Read the current threshold. Returns the lowercase string name, never nil.
---@return "debug"|"info"|"warn"|"error"
sms.log.get_level = function()
  for k, v in pairs(_LEVELS) do
    if v == _level then return k end
  end
  return "info"  -- defensive fallback; shouldn't be reachable
end

---@param msg any
sms.log.debug = function(msg) _emit("sms", "debug", msg) end
---@param msg any
sms.log.info  = function(msg) _emit("sms", "info",  msg) end
---@param msg any
sms.log.warn  = function(msg) _emit("sms", "warn",  msg) end
---@param msg any
sms.log.error = function(msg) _emit("sms", "error", msg) end

---@param name? string  # tag override; auto-derived from caller's chunk source when omitted
---@return sms.log.module
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
    debug = function(msg) _emit(tag, "debug", msg) end,
    info  = function(msg) _emit(tag, "info",  msg) end,
    warn  = function(msg) _emit(tag, "warn",  msg) end,
    error = function(msg) _emit(tag, "error", msg) end,
  }
end
