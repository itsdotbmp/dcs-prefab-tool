-- Mirrors the on-disk shape produced by save_selection on real ME data:
-- statics ride inside `groups` as entries with type='static', and the
-- legacy top-level `statics` array stays empty. Used to verify that
-- split_group_counts pulls them out into the S column.
return {
    ["meta"] = {
        ["name"] = "modern_mixed",
        ["sms_prefab_version"] = "0.1.0",
        ["theatre"] = "Caucasus",
        ["created_utc"] = "2026-05-03T12:00:00Z",
        ["world_anchor"] = { ["x"] = 0, ["y"] = 0 },
    },
    ["groups"] = {
        [1] = { ["name"] = "Vehicle1", ["type"] = "vehicle", ["x"] = 0, ["y"] = 0,
                ["units"] = { [1] = { ["name"] = "U1", ["type"] = "AAV7" } } },
        [2] = { ["name"] = "Plane1",   ["type"] = "plane",   ["x"] = 0, ["y"] = 0,
                ["units"] = { [1] = { ["name"] = "U2", ["type"] = "F-16C_50" } } },
        [3] = { ["name"] = "StaticAS", ["type"] = "static",  ["x"] = 0, ["y"] = 0,
                ["units"] = { [1] = { ["name"] = "S1", ["type"] = "AS32-31A" } } },
    },
    ["statics"]  = {},
    ["zones"]    = { [1] = { ["name"] = "Z1", ["x"] = 0, ["y"] = 0, ["radius"] = 50 } },
    ["drawings"] = {},
}
