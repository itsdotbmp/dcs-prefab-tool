-- dcs-sms framework root.
-- Creates the single global namespace and records the version.
-- Also exposes shared cross-cutting helpers used by entity-wrapper modules
-- (sms.group, sms.unit, sms.area, future sms.static, ...).
-- Idempotent: safe to load multiple times.
sms = sms or {}
sms.version = "0.1.0"

-- Build an entity handle for `name` without verifying the entity exists.
-- Used by sms._make_callable_handle (which adds the existence check) and by
-- sms.events (which needs to wrap units that have just died — Unit.getByName
-- returns nil for them, but a handle whose :is_alive() returns false and
-- whose :get_name() works from the cached name field is still useful for
-- post-mortem event reporting).
sms._make_handle = function(module, name)
  return setmetatable({name = name}, {__index = module})
end

-- Set up a callable handle factory on `module`. After this, calling
-- `module("name")` returns a {name=name} handle (or nil + log) based on
-- whether `dcs_getter(name)` returns non-nil.
--
-- The entity-type string for the log message is derived from the logger's
-- tag field by stripping the "sms." prefix (so the logger tag "sms.group"
-- yields "group" in messages like "couldn't find group 'X'").
--
-- Used by sms.group, sms.unit, and any future cargo-cult entity wrapper.
-- Modules with custom construction logic (multiple paths, snapshot data,
-- etc.) define their own callable instead — see sms.area.
sms._make_callable_handle = function(module, dcs_getter, module_log)
  local type_name = module_log.tag:match("^sms%.(.+)$") or module_log.tag
  setmetatable(module, {
    __call = function(_, name)
      if not dcs_getter(name) then
        module_log.error("couldn't find " .. type_name .. " '" .. tostring(name) .. "'")
        return nil
      end
      return sms._make_handle(module, name)
    end,
  })
end

-- Returns true iff `value` is a table whose metatable __index is `module`.
-- Used for strict handle-type validation in cross-module APIs (e.g. when
-- sms.area's is_unit_in needs to confirm the argument is a real sms.unit
-- handle, not a string or arbitrary {name=...} table).
sms._is_handle_of = function(value, module)
  if type(value) ~= "table" then return false end
  local mt = getmetatable(value)
  return (mt and mt.__index == module) or false
end
