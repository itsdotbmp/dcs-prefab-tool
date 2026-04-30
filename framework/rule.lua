-- dcs-sms framework: rule module (sms.rule).
--
-- Declarative trigger rules: a named, polled, condition-action pair with
-- a small lifecycle (once / continuous / toggle), optional fire cooldown
-- and condition sustain, and a developer escape hatch for instant testing.
--
-- API:
--   sms.rule(name, opts)                  -> handle | nil + log
--   sms.rule.TYPE.{ONCE,CONTINUOUS,TOGGLE}
--
--   r:get_name() / r:get_type() / r:is_active()
--   r:fire()       -- manual fire, bypasses condition / cooldown / sustain
--   r:stop()       -- cancel timer, unregister; idempotent
--   r:reset()      -- clear toggle active, sustain_start, last_fire_time
--   r:set_interval(sec) / r:set_cooldown(sec) / r:set_sustain(sec)
--
--   sms.rule.get(name)        -> handle | nil + log
--   sms.rule.all()            -> list of handles in registration order
--   sms.rule.remove(name)     -> bool
--   sms.rule.test_all()       -> diagnostic (does not affect rule state)
--
-- Each rule owns its own sms.timer.every; no shared scheduler. State
-- machine respects type semantics, cooldown gating, sustain accumulation,
-- and dev_condition bypass. All callbacks invoked via pcall; throws are
-- logged at error and never propagate. Bad input -> log.warn + nil.
--
-- See docs/superpowers/specs/2026-04-30-sms-rule.md.

assert(type(sms) == "table",       "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table",   "framework/log.lua must be loaded first")
assert(type(sms.timer) == "table", "framework/timer.lua must be loaded first")

local log = sms.log.module("sms.rule")

---@class sms.rule
---@field name           string
---@field type           "once"|"continuous"|"toggle"
---@field interval       number
---@field cooldown       number
---@field sustain        number
---@field condition      fun(): any
---@field dev_condition  fun(): any
---@field action         fun()
---@field active         boolean
---@field sustain_start  number|nil
---@field last_fire_time number|nil
---@field timer_handle   sms.timer|nil
---@field registered     boolean
---@overload fun(name: string, opts: table): sms.rule|nil
sms.rule = sms.rule or {}

-- Idempotent registry across module reloads. _rules indexes by name;
-- _order is the registration order for stable iteration in :all() and
-- :test_all(). Both are guarded so reloading rule.lua does NOT clobber
-- rules that are already running.
sms.rule._rules = sms.rule._rules or {}
sms.rule._order = sms.rule._order or {}

sms.rule.TYPE = {
  ONCE       = "once",
  CONTINUOUS = "continuous",
  TOGGLE     = "toggle",
}

local _VALID_TYPES = {
  [sms.rule.TYPE.ONCE]       = true,
  [sms.rule.TYPE.CONTINUOUS] = true,
  [sms.rule.TYPE.TOGGLE]     = true,
}

-- Handle metatable: __index = sms.rule so handle:method() dispatches via
-- sms.rule.method(handle). Identity-checked so callers can't slip arbitrary
-- tables into module functions and get unexpected behavior.
local _handle_mt = { __index = sms.rule }

local function _is_handle(h)
  return type(h) == "table" and getmetatable(h) == _handle_mt
end

-- Accept either a handle or a name string; return a handle from the
-- registry. Returns nil for any other input or for unknown names.
local function _resolve_handle(r)
  if _is_handle(r) then return r end
  if type(r) == "string" then return sms.rule._rules[r] end
  return nil
end

-- Linear-scan removal from _order (registry is small).
local function _remove_from_order(name)
  for i, n in ipairs(sms.rule._order) do
    if n == name then
      table.remove(sms.rule._order, i)
      return
    end
  end
end

-- Replacement semantics (D7): if a rule with the same name is already
-- registered, stop it first.
local function _register(handle)
  local existing = sms.rule._rules[handle.name]
  if existing then
    log.info("replacing existing rule '" .. handle.name .. "'")
    sms.rule.stop(existing)
  end
  sms.rule._rules[handle.name] = handle
  table.insert(sms.rule._order, handle.name)
  handle.registered = true
end

local function _unregister(handle)
  if not handle.registered then return end
  handle.registered = false
  sms.rule._rules[handle.name] = nil
  _remove_from_order(handle.name)
end

local function _cooldown_ok(handle)
  if handle.cooldown <= 0 then return true end
  if handle.last_fire_time == nil then return true end
  return (sms.timer.now() - handle.last_fire_time) >= handle.cooldown
end

-- Run the action via pcall. Returns true on success, false on throw.
-- via_manual = true adds an info-level log line. The dev/manual paths
-- bypass cooldown + sustain at the *call* site (this function does not
-- re-check them); they update last_fire_time on success the same way as
-- a natural fire.
local function _do_fire(handle, via_dev, via_manual)
  if via_manual then
    log.info(handle.name .. ": manual fire")
  end
  local ok, err = pcall(handle.action)
  if not ok then
    log.error(handle.name .. ": action raised: " .. tostring(err))
    -- Throws never update last_fire_time and never unregister ONCE.
    return false
  end
  handle.last_fire_time = sms.timer.now()
  if handle.type == sms.rule.TYPE.ONCE then
    sms.rule.stop(handle)
  end
  return true
end

-- Per-rule scheduler tick. Implements the canonical state machine from
-- the spec ("State machine (canonical)" section).
local function _tick(handle)
  -- dev_condition first: truthy bypasses sustain + cooldown.
  local ok_dev, v_dev = pcall(handle.dev_condition)
  if not ok_dev then
    log.error(handle.name .. ": dev_condition raised: " .. tostring(v_dev))
    v_dev = false
  end
  if v_dev then
    _do_fire(handle, true, false)
    return
  end

  -- Real condition path.
  local ok_real, v_real = pcall(handle.condition)
  if not ok_real then
    log.error(handle.name .. ": condition raised: " .. tostring(v_real))
    v_real = false
  end

  -- Sustain accumulation.
  local effective
  if v_real then
    if handle.sustain_start == nil then
      handle.sustain_start = sms.timer.now()
    end
    effective = (sms.timer.now() - handle.sustain_start) >= handle.sustain
  else
    handle.sustain_start = nil
    effective = false
  end

  -- Type-specific firing logic.
  if handle.type == sms.rule.TYPE.ONCE then
    if effective and _cooldown_ok(handle) then
      _do_fire(handle, false, false)
    end
  elseif handle.type == sms.rule.TYPE.CONTINUOUS then
    if effective and _cooldown_ok(handle) then
      _do_fire(handle, false, false)
    end
  elseif handle.type == sms.rule.TYPE.TOGGLE then
    if effective and not handle.active and _cooldown_ok(handle) then
      _do_fire(handle, false, false)
      handle.active = true
    end
    if not effective then
      handle.active = false
    end
  end
end

-- (Re)start the per-rule timer. Used by construction and by set_interval.
local function _start_timer(handle)
  if handle.timer_handle and handle.timer_handle:is_active() then
    handle.timer_handle:stop()
  end
  handle.timer_handle = sms.timer.every(handle.interval, function()
    if not handle.registered then
      -- Defensive: rule was stopped between scheduling and dispatch.
      return false
    end
    _tick(handle)
  end)
end

-- Validate opts and construct a handle. Returns handle on success,
-- nil + log on failure.
local function _construct(name, opts)
  if type(name) ~= "string" or name == "" then
    log.warn("name must be a non-empty string, got " .. tostring(name))
    return nil
  end
  if type(opts) ~= "table" then
    log.warn("'" .. name .. "': opts must be a table, got " .. type(opts))
    return nil
  end
  if not _VALID_TYPES[opts.type] then
    log.warn("'" .. name .. "': type must be one of sms.rule.TYPE.* (got "
      .. tostring(opts.type) .. ")")
    return nil
  end
  if type(opts.condition) ~= "function" then
    log.warn("'" .. name .. "': condition must be a function, got "
      .. type(opts.condition))
    return nil
  end
  if type(opts.action) ~= "function" then
    log.warn("'" .. name .. "': action must be a function, got "
      .. type(opts.action))
    return nil
  end

  local interval = opts.interval
  if interval == nil then
    interval = 1
  elseif type(interval) ~= "number" or interval <= 0 then
    log.warn("'" .. name .. "': interval must be a positive number, got "
      .. tostring(interval))
    return nil
  end

  local cooldown = opts.cooldown
  if cooldown == nil then
    cooldown = 0
  elseif type(cooldown) ~= "number" or cooldown < 0 then
    log.warn("'" .. name .. "': cooldown must be a non-negative number, got "
      .. tostring(cooldown))
    return nil
  end
  if cooldown > 0 and opts.type == sms.rule.TYPE.ONCE then
    log.warn("'" .. name .. "': cooldown is meaningless on ONCE rules")
    return nil
  end

  local sustain = opts.sustain
  if sustain == nil then
    sustain = 0
  elseif type(sustain) ~= "number" or sustain < 0 then
    log.warn("'" .. name .. "': sustain must be a non-negative number, got "
      .. tostring(sustain))
    return nil
  end

  local dev_condition = opts.dev_condition
  if dev_condition == nil then
    dev_condition = function() end
  elseif type(dev_condition) ~= "function" then
    log.warn("'" .. name .. "': dev_condition must be a function, got "
      .. type(dev_condition))
    return nil
  end

  local handle = setmetatable({
    name           = name,
    type           = opts.type,
    interval       = interval,
    cooldown       = cooldown,
    sustain        = sustain,
    condition      = opts.condition,
    dev_condition  = dev_condition,
    action         = opts.action,
    active         = false,
    sustain_start  = nil,
    last_fire_time = nil,
    timer_handle   = nil,
    registered     = false,
  }, _handle_mt)

  _register(handle)
  _start_timer(handle)
  return handle
end

setmetatable(sms.rule, {
  __call = function(_, name, opts) return _construct(name, opts) end,
})

-- ============================================================
-- Handle methods
-- ============================================================

---@param r sms.rule|string
---@return string|nil
sms.rule.get_name = function(r)
  local h = _resolve_handle(r)
  if not h then
    log.warn("get_name: argument must be a rule handle or registered name")
    return nil
  end
  return h.name
end

---@param r sms.rule|string
---@return string|nil
sms.rule.get_type = function(r)
  local h = _resolve_handle(r)
  if not h then
    log.warn("get_type: argument must be a rule handle or registered name")
    return nil
  end
  return h.type
end

---@param r sms.rule|string
---@return boolean
sms.rule.is_active = function(r)
  local h = _resolve_handle(r)
  if not h then return false end
  if h.type == sms.rule.TYPE.TOGGLE then
    return h.active
  end
  return h.registered == true
end

---@param r sms.rule|string
---@return boolean  # true on success, false on bad handle / throw
sms.rule.fire = function(r)
  local h = _resolve_handle(r)
  if not h then
    log.warn("fire: argument must be a rule handle or registered name")
    return false
  end
  return _do_fire(h, true, true)
end

---@param r sms.rule|string
---@return boolean
sms.rule.stop = function(r)
  local h = _resolve_handle(r)
  if not h then
    log.warn("stop: argument must be a rule handle or registered name")
    return false
  end
  if not h.registered then return false end
  if h.timer_handle then
    h.timer_handle:stop()
    h.timer_handle = nil
  end
  _unregister(h)
  return true
end

---@param r sms.rule|string
---@return boolean
sms.rule.reset = function(r)
  local h = _resolve_handle(r)
  if not h then
    log.warn("reset: argument must be a rule handle or registered name")
    return false
  end
  h.active = false
  h.sustain_start = nil
  h.last_fire_time = nil
  return true
end

---@param r sms.rule|string
---@param sec number  # positive
---@return boolean
sms.rule.set_interval = function(r, sec)
  local h = _resolve_handle(r)
  if not h then
    log.warn("set_interval: argument must be a rule handle or registered name")
    return false
  end
  if type(sec) ~= "number" or sec <= 0 then
    log.warn("'" .. h.name .. "': set_interval: must be a positive number, got "
      .. tostring(sec))
    return false
  end
  h.interval = sec
  if h.registered then _start_timer(h) end
  return true
end

---@param r sms.rule|string
---@param sec number  # non-negative; rejected on ONCE if > 0
---@return boolean
sms.rule.set_cooldown = function(r, sec)
  local h = _resolve_handle(r)
  if not h then
    log.warn("set_cooldown: argument must be a rule handle or registered name")
    return false
  end
  if type(sec) ~= "number" or sec < 0 then
    log.warn("'" .. h.name .. "': set_cooldown: must be a non-negative number, got "
      .. tostring(sec))
    return false
  end
  if sec > 0 and h.type == sms.rule.TYPE.ONCE then
    log.warn("'" .. h.name .. "': set_cooldown is meaningless on ONCE rules")
    return false
  end
  h.cooldown = sec
  return true
end

---@param r sms.rule|string
---@param sec number  # non-negative
---@return boolean
sms.rule.set_sustain = function(r, sec)
  local h = _resolve_handle(r)
  if not h then
    log.warn("set_sustain: argument must be a rule handle or registered name")
    return false
  end
  if type(sec) ~= "number" or sec < 0 then
    log.warn("'" .. h.name .. "': set_sustain: must be a non-negative number, got "
      .. tostring(sec))
    return false
  end
  h.sustain = sec
  h.sustain_start = nil  -- clear in-flight accumulation per spec D8
  return true
end

-- ============================================================
-- Registry API
-- ============================================================

---@param name string
---@return sms.rule|nil
sms.rule.get = function(name)
  if type(name) ~= "string" then
    log.warn("get: name must be a string, got " .. type(name))
    return nil
  end
  local h = sms.rule._rules[name]
  if not h then
    log.warn("get: no rule registered with name '" .. name .. "'")
    return nil
  end
  return h
end

---@return sms.rule[]
sms.rule.all = function()
  local out = {}
  for i, name in ipairs(sms.rule._order) do
    out[i] = sms.rule._rules[name]
  end
  return out
end

---@param name string
---@return boolean
sms.rule.remove = function(name)
  if type(name) ~= "string" then
    log.warn("remove: name must be a string, got " .. type(name))
    return false
  end
  local h = sms.rule._rules[name]
  if not h then
    log.warn("remove: no rule registered with name '" .. name .. "'")
    return false
  end
  return sms.rule.stop(h)
end

-- Diagnostic: pcall every condition / dev_condition / action across all
-- registered rules. Logs PASS/FAIL per call. Does NOT change rule state
-- (no last_fire_time updates, no TOGGLE flips, no ONCE unregister) — see
-- spec D10. The intent is "verify my callbacks compile and don't crash"
-- — not "exercise the firing logic".
sms.rule.test_all = function()
  log.info("test_all: starting (" .. #sms.rule._order .. " rules)")
  -- Iterate over a snapshot of names; even though test_all does not change
  -- registration, this guards against a hypothetical user callback that
  -- constructs / removes rules during the diagnostic.
  local snapshot = {}
  for i, n in ipairs(sms.rule._order) do snapshot[i] = n end
  for _, name in ipairs(snapshot) do
    local handle = sms.rule._rules[name]
    if handle then
      for _, kind in ipairs({"condition", "dev_condition", "action"}) do
        local fn = handle[kind]
        local ok, err = pcall(fn)
        if ok then
          log.info("test_all: " .. name .. " " .. kind .. ": PASS")
        else
          log.error("test_all: " .. name .. " " .. kind .. ": FAIL: "
            .. tostring(err))
        end
      end
    end
  end
  log.info("test_all: done")
end
