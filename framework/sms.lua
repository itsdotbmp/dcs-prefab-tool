-- dcs-sms framework root.
-- Creates the single global namespace and records the version.
-- Idempotent: safe to load multiple times.
sms = sms or {}
sms.version = "0.1.0"
