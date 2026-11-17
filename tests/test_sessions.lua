-- Sessions.lua (November 17): loot counted once (a player on CurseForge: sold loot counted
-- as loot and again as gold), pause, usual pace and the full view's lines.
local T = ...
local ns, S = T.ns, T.S

local A, B = 990101, 990102   -- items no other test uses

-- A running session on this character with loot already in it, each item worth 100c.
local function session(loot)
  ns.db.liveSession = { t = S.now - 600, resume = S.now - 600, active = 0, char = ns.CharKey(), money = {}, loot = loot }
  return ns.db.liveSession
end
local function withValues(fn)
  local real = ns.LootValue
  ns.LootValue = function(_, id) return (id == A or id == B) and 100 or 0 end
  local ok, err = pcall(fn)
  ns.LootValue = real
  ns.db.liveSession = nil
  S.bags[A], S.bags[B], S.bank[A] = nil, nil, nil
  if not ok then error(err, 0) end
end

T.test("Sessions: loot sold during the session counts once, as gold", function()
  withValues(function()
    S.items[A] = { name = "Session Test Cloth" }
    local s = session({ [A] = 5, [B] = 2 })
    S.bags[A], S.bags[B] = 5, 2
    T.eq(ns:SessionTotals().loot, 700, "all of it, still in the bags")
    -- Sold 2 to a vendor: they're gold now (History.lua passes the item ID).
    ns:SessionSold(A, 2)
    S.bags[A] = 3
    ns:SessionMoney("vendorSell", 200)
    local st = ns:SessionTotals()
    T.eq(st.loot, 500, "3 + 2 left as loot")
    T.eq(st.gained, 200, "the 2 sold, as gold")
    -- An auction sale names the item.
    ns:SessionSold("Session Test Cloth", 1)
    T.eq(s.sold[A], 3)
    -- Never more sold than looted.
    ns:SessionSold(A, 50)
    T.eq(s.sold[A], 5)
    S.bags[A] = 10   -- (bought more: still only what was looted, less what was sold)
    T.eq(ns:SessionTotals().loot, 200, "only B left")
  end)
end)

T.test("Sessions: loot no longer held drops out; posted auctions still count", function()
  withValues(function()
    session({ [A] = 4 })
    S.bags[A], S.bank[A] = 1, 1
    T.eq(ns:SessionTotals().loot, 200, "disenchanted or used: only what's left")
    ns.db.myAuctions = ns.db.myAuctions or {}
    ns.db.myAuctions[ns.CharKey()] = { list = { { id = A, q = 2 }, { id = A, q = 5, sold = true } } }
    T.eq(ns:SessionTotals().loot, 400, "2 on the auction house, not sold yet")
    ns.db.myAuctions[ns.CharKey()] = nil
    S.bags[A], S.bank[A] = 0, 0
    local st = ns:SessionTotals()
    T.eq(st.loot, 0)
    T.eq(#st.items, 0)
  end)
end)

T.test("Sessions: items without a price are counted apart", function()
  withValues(function()
    session({ [A] = 1, [990103] = 3 })
    S.bags[A], S.bags[990103] = 1, 3
    local st = ns:SessionTotals()
    T.eq(st.loot, 100)
    T.eq(st.unpriced, 3)
    S.bags[990103] = nil
  end)
end)

T.test("Sessions: pause stops the clock and the counting", function()
  withValues(function()
    local s = session({})
    T.eq(ns:SessionTotals().secs, 600)
    ns:PauseGeneralSession(true)
    T.ok(s.paused, "paused")
    T.eq(s.active, 600, "the time so far banked")
    ns:SessionMoney("loot", 500)
    T.eq(s.money.loot, nil, "nothing counted while paused")
    S.now = S.now + 300
    T.eq(ns:SessionTotals().secs, 600, "the clock stood still")
    ns:PauseGeneralSession(false)
    T.eq(s.paused, nil)
    S.now = S.now + 60
    T.eq(ns:SessionTotals().secs, 660, "and runs again")
    ns:SessionMoney("loot", 500)
    T.eq(s.money.loot, 500)
    S.now = S.now - 360
  end)
end)

T.test("Sessions: gold an hour after 5 minutes, usual and best pace", function()
  T.eq(ns.SessionRate({ secs = 200, earned = 100 }), nil, "too short")
  T.eq(ns.SessionRate({ secs = 3600, earned = 1000, spent = 200, loot = 400 }), 1200, "gold and loot")
  local saved = ns.db.sessions
  ns.db.sessions = {
    { kind = "general", secs = 3600, earned = 1000 },
    { kind = "general", secs = 300, earned = 99999 },   -- under 10 minutes: not counted
    { kind = "general", secs = 3600, earned = 3000 },
  }
  T.eq(ns:SessionUsual(), nil, "needs 3 sessions")
  ns.db.sessions[#ns.db.sessions + 1] = { kind = "general", secs = 1800, earned = 1000 }   -- 2000 an hour
  ns.db.sessions[#ns.db.sessions + 1] = { kind = "general", secs = 3600, earned = 4000 }
  local u = ns:SessionUsual()
  T.eq(u and u.n, 4)
  T.eq(u and u.usual, 2500, "the median of 1000, 2000, 3000, 4000")
  T.eq(u and u.best, 4000)
  ns.db.sessions = saved
end)

T.test("Sessions: the full view's lines", function()
  local st = { secs = 900, gained = 300, loot = 500, perHour = 3200, unpriced = 2,
    items = { { id = A, n = 3, value = 300 }, { id = B, n = 2, value = 200 } } }
  local s = { money = { vendorSell = 500, repair = -200 } }
  local spec = ns.SessionDetailLines(st, s, { usual = 2000, best = 5000, n = 3 }, B)
  T.eq(spec[1].kind, "head")
  T.eq(spec[1].left, "Gold")
  local rows, flashed, notes = 0, nil, 0
  for _, e in ipairs(spec) do
    if e.id then rows = rows + 1 end
    if e.flash then flashed = e.id end
    if e.kind == "note" then notes = notes + 1 end
  end
  T.eq(rows, 2, "a row per item")
  T.eq(flashed, B, "what just came in is lit")
  T.ok(notes >= 2, "the unpriced note and the loot note")
  local noUsual = ns.SessionDetailLines(st, s, nil, nil)
  local said
  for _, e in ipairs(noUsual) do if e.left and e.left:find("after 3 sessions", 1, true) then said = true end end
  T.ok(said, "says when the usual pace shows")
end)
