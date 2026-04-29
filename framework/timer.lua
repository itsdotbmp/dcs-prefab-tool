-- dcs-sms framework: timer module (sms.timer).
--
-- First behavioral primitive in the framework. Wraps DCS's native
-- timer.scheduleFunction / timer.removeFunction / timer.getTime in
-- an idiomatic surface for "run this in N seconds" and "run this every
-- N seconds" patterns.
--
-- API:
--   sms.timer.after(seconds, fn)              -> handle | nil + log
--   sms.timer.every(seconds, fn, max?)        -> handle | nil + log
--   h:stop()                                  -> bool
--   h:is_active()                             -> bool (silent probe)
--   h:get_remaining()                         -> number | nil + log
--
-- For repeating timers, fn returning false self-cancels. The optional
-- max arg on every() also caps the total iterations. User errors in fn
-- are caught via pcall and logged — bad user code never breaks the
-- framework.
--
-- Sim-time-based via timer.getTime(); pauses with DCS.
--
-- See docs/superpowers/specs/2026-04-26-framework-timer-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
local log = sms.log.module("sms.timer")

---@class sms.timer
---@field kind            "after"|"every"
---@field active          boolean
---@field next_fire_time  number|nil
---@field interval        number|nil  # only on `every` handles
---@field iterations      integer|nil # only on `every` handles
---@field max             integer|nil # only on `every` handles
---@field id              integer
sms.timer = sms.timer or {}

-- Handle metatable. __index points at the module table itself so
-- handle:method() dispatches via sms.timer.method(handle). Identity-
-- checked so callers can't slip arbitrary tables into module functions
-- and get unexpected behavior.
local _handle_mt = {__index = sms.timer}

-- Returns true if h is a real timer handle (created by after/every).
local function _is_handle(h)
  return type(h) == "table" and getmetatable(h) == _handle_mt
end

---@param seconds number  # non-negative
---@param fn fun()
---@return sms.timer|nil
sms.timer.after = function(seconds, fn)
  if type(seconds) ~= "number" or seconds < 0 then
    log.warn("after: seconds must be a non-negative number, got " .. tostring(seconds))
    return nil
  end
  if type(fn) ~= "function" then
    log.warn("after: fn must be a function, got " .. type(fn))
    return nil
  end

  -- `kind` is unused at runtime today; carried so a future debug aid
  -- (e.g. sms.timer.list(), explicitly out of scope per the spec) can
  -- distinguish one-shot timers from repeating ones.
  local now = timer.getTime()
  local handle = setmetatable({
    kind = "after",
    active = true,
    next_fire_time = now + seconds,
  }, _handle_mt)

  handle.id = timer.scheduleFunction(function(_, t)
    handle.active = false
    handle.next_fire_time = nil
    local ok, err = pcall(fn)
    if not ok then
      log.error("after: user fn raised: " .. tostring(err))
    end
    return nil
  end, nil, handle.next_fire_time)

  return handle
end

---@param seconds number  # positive
---@param fn fun(): boolean?  # return false to self-cancel
---@param max? integer
---@return sms.timer|nil
sms.timer.every = function(seconds, fn, max)
  if type(seconds) ~= "number" or seconds <= 0 then
    log.warn("every: seconds must be a positive number, got " .. tostring(seconds))
    return nil
  end
  if type(fn) ~= "function" then
    log.warn("every: fn must be a function, got " .. type(fn))
    return nil
  end
  if max ~= nil and (type(max) ~= "number" or max <= 0) then
    log.warn("every: max must be a positive number or nil, got " .. tostring(max))
    return nil
  end

  local now = timer.getTime()
  local handle = setmetatable({
    kind = "every",
    active = true,
    interval = seconds,
    iterations = 0,
    max = max,
    next_fire_time = now + seconds,
  }, _handle_mt)

  handle.id = timer.scheduleFunction(function(_, t)
    -- Note: handle.active stays true while fn runs. A user calling
    -- :is_active() from inside their `every` callback sees true; the
    -- handle only deactivates AFTER fn returns false or max is reached.
    -- (This differs from `after`, which deactivates before calling fn
    -- because the post-fire state is final.)
    handle.iterations = handle.iterations + 1
    local ok, result = pcall(fn)
    if not ok then
      log.error("every: user fn raised: " .. tostring(result))
      -- Caught errors continue iterating per spec; clobber `result`
      -- so the error message string isn't mistaken for a self-cancel.
      result = nil
    end
    if result == false then
      handle.active = false
      handle.next_fire_time = nil
      return nil
    end
    if handle.max and handle.iterations >= handle.max then
      handle.active = false
      handle.next_fire_time = nil
      return nil
    end
    -- Rebase from t (actual fire time) instead of next_fire_time so
    -- DCS-side late dispatch doesn't compound into runaway drift.
    handle.next_fire_time = t + handle.interval
    return handle.next_fire_time
  end, nil, handle.next_fire_time)

  return handle
end

---@param h sms.timer
---@return boolean
sms.timer.stop = function(h)
  if not _is_handle(h) then
    log.warn("stop: argument must be a timer handle")
    return false
  end
  if not h.active then return false end
  h.active = false
  h.next_fire_time = nil
  pcall(timer.removeFunction, h.id)
  return true
end

---@param h sms.timer
---@return boolean
sms.timer.is_active = function(h)
  if not _is_handle(h) then return false end
  return h.active == true
end

---@param h sms.timer
---@return number|nil  # seconds until next fire
sms.timer.get_remaining = function(h)
  if not _is_handle(h) then
    log.warn("get_remaining: argument must be a timer handle")
    return nil
  end
  if not h.active or not h.next_fire_time then
    log.warn("get_remaining: timer is not active")
    return nil
  end
  return h.next_fire_time - timer.getTime()
end

-- Current simulation time (seconds since mission start). Thin wrapper so
-- mission code that timestamps events stays inside the sms.* idiom rather
-- than reaching for DCS's `timer.getTime` directly. Sim-time, pauses with DCS.
---@return number  # sim-time seconds since mission start
sms.timer.now = function()
  return timer.getTime()
end
