-- Core.lua freeze watch (Frank, November 17: the game froze while hovering tooltips): a
-- slow frame is kept with Forever Ledger's share and what the profiler named.
local T = ...
local ns = T.ns

T.test("Freeze watch: slow frames kept, short ones not, Forever Ledger's share", function()
  ns.db.freezeLog = nil
  ns.NoteFrame(0.1, 5, "Tooltip lines", 5, nil, nil)
  T.eq(ns.db.freezeLog, nil, "a normal frame isn't noted")
  ns.NoteFrame(0.8, 12.4, "Tooltip lines", 9, 2589, { { name = "SomeAddon", v = 640 } })
  local e = ns.db.freezeLog[1]
  T.eq(e.ms, 800)
  T.eq(e.ours, 12)
  T.eq(e.what, "Tooltip lines")
  T.eq(e.item, 2589)
  T.eq(e.addons[1], "SomeAddon 640 ms")
  ns.NoteFrame(0.5, 1, "Tiny", 1, nil, nil)
  T.eq(ns.db.freezeLog[2].what, nil, "a share under 5 ms isn't named")
  local text = table.concat(ns.FreezeLines(8), "\n")
  T.ok(text:find("800 ms", 1, true), "listed")
  T.ok(text:find("SomeAddon 640 ms", 1, true), "with the other addon")
  for _ = 1, 30 do ns.NoteFrame(0.3, 0, nil, 0, nil, nil) end
  T.eq(#ns.db.freezeLog, 20, "the last 20 kept")
  ns.db.freezeLog = nil
  T.ok(table.concat(ns.FreezeLines(8), "\n"):find("none seen", 1, true))
end)
