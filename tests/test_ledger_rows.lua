-- The Ledger draws only the rows in view, the rest as you scroll (Frank's tenth /fl perf,
-- November 21). Rows are made as they come into view, so a jump down the scroll bar leaves
-- gaps in the pool: a refresh and the selection marks must cope (Codex review, November 21:
-- rows[21]:Hide() on a missing row).
local T = ...
local ns, S = T.ns, T.S
local L = ns._ledgerTest
local ME = ns.CharKey()

T.test("Ledger rows: a jump down the list and back, then a refresh, with gaps in the rows", function()
  local real = { ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths, ns.db.settings.ledger }
  local ok, err = pcall(function()
    ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths = {}, {}, {}
    ns.db.sales = {}
    -- (Each an hour apart, so none are grouped into one row.)
    for i = 1, 120 do ns.db.sales[i] = { t = S.now - i * 3600, c = ME, n = "Row Test " .. i, q = 1, a = 10 } end
    ns.db.settings.ledger = { tab = "sales", range = "all", char = "all", sort = {}, group = "all", rarity = "all" }
    if not L.frame() then ns:BuildLedger(S.dummy()) end
    local F = L.frame()
    F.IsShown = function() return true end
    local top = 0
    F.sf.GetVerticalScroll = function() return top end
    F.sf.GetHeight = function() return 200 end   -- (10 rows of 20)
    ns:RefreshLedger()
    T.runTimers()   -- (the list is built over several frames, then drawn)
    local function made()
      local n, max = 0, 0
      for i in pairs(L.rows()) do n = n + 1; if i > max then max = i end end
      return n, max
    end
    local n = made()
    T.ok(n > 0 and n < 120, "only the rows in view and a few more: " .. n)
    top = 64 * 20
    L.drawVisible()
    top = 43 * 20
    L.drawVisible()
    local _, max = made()
    T.ok(max >= 80, "rows far down made: " .. max)
    T.eq(L.rows()[25], nil, "a gap in the rows")
    ns:RefreshLedger()   -- (hid every row with rows[i]:Hide(), and stopped at the gap)
    T.runTimers()
  end)
  ns.db.sales, ns.db.purchases, ns.db.vendorLog, ns.db.ledgerMonths, ns.db.settings.ledger =
    real[1], real[2], real[3], real[4], real[5]
  local F = L.frame()
  if F then F.IsShown = function() return false end end
  T.runTimers()
  assert(ok, err)
end)
