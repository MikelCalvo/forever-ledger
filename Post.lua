local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- The Post tab (redesign build step 4, November 15; planning/REDESIGN_PLAN.md sections 2
-- and 8, mockup "AH: Post tab"). Inside the auction house window (AHTabs.lua):
--   left   your bags, grouped (Groups.lua), each with a price ready and a mark from the
--          sell suggestion (SellAdvice.lua): Post, Keep, Vendor, Disenchant
--   right  the item being posted: how many, the price each (from its post rule:
--          Groups.lua RuleFor), how long, the deposit and what you get; Post, Skip,
--          Previous; under it the cheapest listings at the last scan
-- Posting is the game's own C_AuctionHouse.PostCommodity / PostItem, from your click or a
-- mouse wheel tick (Blizzard's rule: one hardware action each), never by itself. When the
-- game asks for a confirmation (ConfirmPostCommodity / ConfirmPostItem), the next click or
-- tick confirms. The price never goes below the rule's floor or what a vendor pays after
-- the cut (sell protection, as SellGuard.lua does on Blizzard's Sell page).
-- Middle-click a row to skip it for this visit; Scroll to post (off at each visit, Esc
-- turns it off) posts the highlighted one with each wheel tick.
---------------------------------------------------------------------------

local AH = C_AuctionHouse
local HOURS_TO_INDEX = { [2] = 1, [8] = 2, [24] = 3 }   -- Forever: 1/2/3 = 2/8/24 hours (Deposits.lua)
local INDEX_HOURS = { 2, 8, 24 }

---------------------------------------------------------------------------
-- The price (pure, for the tests)
---------------------------------------------------------------------------
-- rule: a post rule's fields (Groups.lua RULE_DEFAULTS.post) or nil when posting is off.
-- usual, cheapest: copper or nil. vendorFloor: the least price that still beats a vendor
-- after the cut, or nil. Returns { price, floor, why, skip }.
function ns.PostPrice(rule, usual, cheapest, vendorFloor)
  local out = {}
  if not rule then out.why = "No post rule for it (Off): type a price."; return out end
  local floor = 0
  if usual and usual > 0 and rule.floorPct then floor = math.floor(usual * rule.floorPct / 100) end
  if vendorFloor and vendorFloor > floor then floor = vendorFloor end
  out.floor = floor > 0 and floor or nil
  local price
  if cheapest and cheapest > 0 then
    price = cheapest - (rule.undercut or 0)
    out.why = (rule.undercut or 0) > 0 and ("%s under the cheapest (%s)"):format(ns.MoneyPlain(rule.undercut), ns.MoneyPlain(cheapest))
      or ("the cheapest (%s)"):format(ns.MoneyPlain(cheapest))
  elseif usual and usual > 0 and rule.start ~= "cheapest" then
    price = usual
    out.why = "the usual price (none listed now)"
  else
    out.why = "No price yet: scan, or type one."
    return out
  end
  if out.floor and price < out.floor then
    if rule.belowFloor == "floor" then
      price = out.floor
      out.why = ("your floor (the cheapest, %s, is under it)"):format(ns.MoneyPlain(cheapest or 0))
    else
      out.skip = true
      out.why = ("Not posted: the cheapest (%s) is under your floor (%s)."):format(ns.MoneyPlain(cheapest or 0), ns.MoneyPlain(out.floor))
    end
  end
  out.price = math.max(1, math.floor(price))
  return out
end

-- The least price each that brings at least what a vendor pays, after the cut.
function ns:PostVendorFloor(id)
  local vendor = ns:GetSellPrice(id)
  if not vendor or vendor <= 0 then return nil end
  local cut = (ns.neutralAH and 15 or (ns.db.settings.ahCut or 5)) / 100
  local p = math.max(1, math.floor(vendor / (1 - cut)))
  for _ = 1, 5 do
    if ns:AfterCut(p, ns.neutralAH) >= vendor then break end
    p = p + 1
  end
  return p
end

local function usualOf(id)
  local stats = ns.PriceStats and ns:PriceStats(id, "month")
  if stats and stats.points and stats.points >= 3 and stats.usual then return math.floor(stats.usual) end
  local u = ns.UsualPrice and ns:UsualPrice(id)
  return u and math.floor(u) or nil
end

local function cheapestOf(id, link)
  local rec = (ns.db.prices[ns.MarketKey()] or {})[id]
  local cheapest = rec and not rec.none and rec.m or nil
  -- Gear: this version's cheapest ("of the Monkey"), as the price helper does.
  if link and cheapest and ns.VersionOfLink and ns.SuffixPrice then
    local suffix = ns:VersionOfLink(id, link)
    local m = suffix and ns:SuffixPrice(id, suffix)
    if m and m > 0 then cheapest = m end
  end
  return cheapest, rec
end

---------------------------------------------------------------------------
-- Your bags
---------------------------------------------------------------------------
local entries = {}   -- the list: { id, count, link, bag, slot, gear, group, groupName, mark, price... }
local cur = 1        -- the highlighted one
local skipped = {}   -- [key] = true: middle-clicked, for this visit
local posted = {}    -- [key] = true: posted this visit
local edits = {}     -- [key] = { price, qty, hours } typed in this visit
local frame
local scrollPost = false
local pending        -- a post waiting for the game's confirmation: { fn, args }

local function keyOf(e) return e.gear and (e.bag .. ":" .. e.slot) or tostring(e.id) end

local MARK = { ah = "Post", middle = "Post", keep = "Keep", vendor = "Vendor", de = "Disenchant" }
local MARK_COLOR = { Post = { 0.62, 0.91, 0.86 }, Keep = { 0.73, 0.74, 0.78 }, Vendor = { 0.94, 0.83, 0.54 },
  Disenchant = { 0.82, 0.66, 0.96 }, Skipped = { 0.55, 0.55, 0.55 }, Posted = { 0.5, 0.83, 0.61 } }

local function groupFor(id)
  for _, gid in ipairs(ns.ItemGroups and ns:ItemGroups(id) or {}) do
    local info = ns:GroupInfo(gid)
    if info and info.kind == "builtin" then
      local parent = info.parent and ns:GroupInfo(info.parent)
      return gid, parent and (parent.name .. " · " .. info.name) or info.name
    end
  end
  return "misc", "Miscellaneous"
end

local orderOf = {}
for i, g in ipairs(ns.BUILTIN_GROUPS or {}) do orderOf[g.id] = i end

local function readBags()
  local byId, list = {}, {}
  local CC = C_Container
  if not (CC and CC.GetContainerNumSlots and CC.GetContainerItemInfo) then return list end
  local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  for bag = 0, last do
    for slot = 1, CC.GetContainerNumSlots(bag) or 0 do
      local info = CC.GetContainerItemInfo(bag, slot)
      if info and info.itemID and not info.isBound and (info.quality or 1) > 0 then
        local id = info.itemID
        local gear = ns.IsGearItem and ns:IsGearItem(id)
        if gear then
          list[#list + 1] = { id = id, count = 1, link = info.hyperlink, bag = bag, slot = slot, gear = true }
        elseif byId[id] then
          byId[id].count = byId[id].count + (info.stackCount or 1)
        else
          byId[id] = { id = id, count = info.stackCount or 1, link = info.hyperlink, bag = bag, slot = slot }
          list[#list + 1] = byId[id]
        end
      end
    end
  end
  return list
end

local function verdictMark(e)
  if not (ns.SellVerdict and ns.SellFacts) then return "Post" end
  local ok, v = pcall(function() return ns.SellVerdict(ns:SellFacts(e.id, false, true)) end)
  if not ok or not v then return "Post" end
  if v.deFirst or v.kind == "de" then return "Disenchant" end
  return MARK[v.kind] or "Post"
end

-- Works out each entry's price and quantity from its rule (and what you typed).
local function price(e)
  -- (Its own lines: "ns.RuleFor and ns:RuleFor(...)" would keep only the first value.)
  local rule, from
  if ns.RuleFor then rule, from = ns:RuleFor(e.id, "post") else rule = ns.RULE_DEFAULTS and ns.RULE_DEFAULTS.post end
  e.rule, e.ruleFrom = rule, from or "Default"
  e.usual = usualOf(e.id)
  e.cheapest, e.rec = cheapestOf(e.id, e.gear and e.link)
  local p = ns.PostPrice(rule, e.usual, e.cheapest, ns:PostVendorFloor(e.id))
  e.suggested, e.floor, e.why, e.skipRule = p.price, p.floor, p.why, p.skip
  local typed = edits[keyOf(e)] or {}
  e.price = typed.price or e.suggested
  e.hours = typed.hours or (rule and rule.hours) or 24
  local keep = (rule and rule.keep) or 0
  e.qty = typed.qty or math.max(0, e.count - keep)
  if e.gear then e.qty = math.min(e.qty, 1) end
end

local refresh

function ns:RefreshPost()
  local list = readBags()
  for _, e in ipairs(list) do
    e.group, e.groupName = groupFor(e.id)
    e.mark = verdictMark(e)
    price(e)
  end
  local wantAll = frame and frame.showAll
  local out = {}
  for _, e in ipairs(list) do
    if wantAll or e.mark == "Post" then out[#out + 1] = e end
  end
  table.sort(out, function(a, b)
    local oa, ob = orderOf[a.group] or 999, orderOf[b.group] or 999
    if oa ~= ob then return oa < ob end
    local na, nb = ns.ItemName(a.id), ns.ItemName(b.id)
    if na ~= nb then return na < nb end
    return keyOf(a) < keyOf(b)
  end)
  local wasKey = entries[cur] and keyOf(entries[cur])
  entries = out
  cur = 1
  for i, e in ipairs(entries) do if keyOf(e) == wasKey then cur = i; break end end
  -- Start on one that can be posted.
  local function usable(e) local k = keyOf(e); return not skipped[k] and not posted[k] end
  if entries[cur] and not usable(entries[cur]) then
    for i = 1, #entries do if usable(entries[i]) then cur = i; break end end
  end
  if refresh then refresh() end
end

---------------------------------------------------------------------------
-- Posting
---------------------------------------------------------------------------
local function locationOf(e)
  if not (ItemLocation and ItemLocation.CreateFromBagAndSlot) then return end
  -- The slot may have changed since the list was read: find the item again.
  local CC = C_Container
  local info = CC.GetContainerItemInfo(e.bag, e.slot)
  if not (info and info.itemID == e.id) then
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, last do
      for slot = 1, CC.GetContainerNumSlots(bag) or 0 do
        local i2 = CC.GetContainerItemInfo(bag, slot)
        if i2 and i2.itemID == e.id and not i2.isBound and (not e.gear or i2.hyperlink == e.link) then
          e.bag, e.slot = bag, slot
          return ItemLocation:CreateFromBagAndSlot(bag, slot)
        end
      end
    end
    return
  end
  return ItemLocation:CreateFromBagAndSlot(e.bag, e.slot)
end

local function say(text) if frame then frame.note:SetText(text or "") end end

local function nextUsable(from, step)
  local i = from
  for _ = 1, #entries do
    i = i + step
    if i < 1 or i > #entries then return from end
    local k = keyOf(entries[i])
    if not skipped[k] and not posted[k] then return i end
  end
  return from
end

-- Post the highlighted item (a click on Post, or a wheel tick with Scroll to post on).
local function postCurrent()
  if pending then
    -- The game asked to confirm the last one: this click or tick confirms it.
    local p = pending
    pending = nil
    local ok, err = pcall(p.fn, unpack(p.args))
    if not ok then say("Couldn't confirm: " .. tostring(err)) end
    posted[p.key] = true
    cur = nextUsable(cur, 1)
    if refresh then refresh() end
    return
  end
  local e = entries[cur]
  if not e then return end
  local k = keyOf(e)
  if skipped[k] or posted[k] then cur = nextUsable(cur, 1); refresh(); return end
  if not (e.price and e.price > 0) then say("Type a price first."); return end
  if e.floor and e.price < e.floor then
    say(("Under your floor (%s): type a higher price, or change the rule."):format(ns.MoneyPlain(e.floor)))
    return
  end
  if not e.qty or e.qty < 1 then say("Nothing to post (Keep holds them all)."); return end
  if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
    say("The auction house is busy: try again in a moment.")
    return
  end
  local loc = locationOf(e)
  if not loc then say("Couldn't find it in your bags any more."); ns:RefreshPost(); return end
  local dur = HOURS_TO_INDEX[e.hours] or 3
  local commodity = AH.GetItemCommodityStatus and AH.GetItemCommodityStatus(loc) == 2
  local fn, confirmFn, args
  if commodity then
    fn, confirmFn, args = AH.PostCommodity, AH.ConfirmPostCommodity, { loc, dur, e.qty, e.price }
  else
    fn, confirmFn, args = AH.PostItem, AH.ConfirmPostItem, { loc, dur, 1, nil, e.price }
  end
  if not fn then say("This game client can't post from here: use Blizzard's Sell tab."); return end
  local ok, needsConfirm = pcall(fn, unpack(args))
  if not ok then say("Couldn't post: " .. tostring(needsConfirm)); return end
  if needsConfirm == true and confirmFn then
    pending = { fn = confirmFn, args = args, key = k }
    say("The auction house asks you to confirm this one: click Confirm post (or tick the wheel).")
    if refresh then refresh() end
    return
  end
  posted[k] = true
  say(("Posted %d %s at %s each."):format(e.qty, ns.ItemName(e.id), ns.MoneyPlain(e.price)))
  cur = nextUsable(cur, 1)
  if refresh then refresh() end
end
ns.PostCurrent = postCurrent   -- (tests)

---------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------
local ROW_H, LEFT_W = 18, 340

local function setScrollPost(on)
  scrollPost = on and true or false
  if not frame then return end
  frame.scrollSwitch:SetChecked(scrollPost)
  frame:EnableKeyboard(scrollPost)
  frame.listBox:SetBackdropShown(scrollPost)
end

local function row(i)
  local r = frame.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, frame.content)
  r:SetHeight(ROW_H)
  r:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
  r.bg = T:Fill(r, { 1, 1, 1, 0 })
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.12)
  r.heading = T:Text(r, 10, T.dim)
  r.heading:SetPoint("LEFT", 6, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 6, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.mark = T:Text(r, 10)
  r.mark:SetPoint("RIGHT", -4, 0)
  r.mark:SetWidth(66)
  r.mark:SetJustifyH("RIGHT")
  r.price = T:Text(r, 11)
  r.price:SetPoint("RIGHT", r.mark, "LEFT", -6, 0)
  r.name = T:Text(r, 11)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
  r.name:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r:SetScript("OnClick", function(self, button)
    if not self.index then return end
    local e = entries[self.index]
    if button == "MiddleButton" then
      local k = keyOf(e)
      skipped[k] = not skipped[k] or nil
      if skipped[k] and cur == self.index then cur = nextUsable(cur, 1) end
    else
      cur = self.index
      pending = nil
    end
    refresh()
  end)
  r:SetScript("OnEnter", function(self)
    if not self.index then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local e = entries[self.index]
    if e.link then GameTooltip:SetHyperlink(e.link) else GameTooltip:SetItemByID(e.id) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to post this one next. Middle-click to skip it this visit (again to bring it back).", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.rows[i] = r
  return r
end

local function drawList()
  local lines, lastGroup = {}, nil
  for i, e in ipairs(entries) do
    if e.groupName ~= lastGroup then
      lines[#lines + 1] = { heading = e.groupName }
      lastGroup = e.groupName
    end
    lines[#lines + 1] = { index = i }
  end
  local w = frame.sf:GetWidth() - 12
  for n, line in ipairs(lines) do
    local r = row(n)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -(n - 1) * ROW_H)
    r:SetWidth(w)
    r.index = line.index
    if line.heading then
      r.heading:SetText(line.heading:upper())
      r.heading:Show()
      for _, part in ipairs({ r.icon, r.name, r.price, r.mark }) do part:Hide() end
      r.bg:SetColorTexture(1, 1, 1, 0)
      r:EnableMouse(false)
    else
      local e = entries[line.index]
      local k = keyOf(e)
      r:EnableMouse(true)
      r.heading:Hide()
      for _, part in ipairs({ r.icon, r.name, r.price, r.mark }) do part:Show() end
      r.icon:SetTexture(ns:ItemIcon(e.id))
      local label = (posted[k] and "Posted") or (skipped[k] and "Skipped") or e.mark
      r.name:SetText(ns.ItemName(e.id) .. (e.count > 1 and (" x" .. e.count) or ""))
      r.price:SetText(e.price and ns.MoneyPlain(e.price) or "|cff888888-|r")
      local c = MARK_COLOR[label] or MARK_COLOR.Post
      r.mark:SetText(label:upper())
      r.mark:SetTextColor(c[1], c[2], c[3])
      local dim = posted[k] or skipped[k]
      r.name:SetAlpha(dim and 0.45 or 1)
      r.price:SetAlpha(dim and 0.45 or 1)
      r.icon:SetDesaturated(dim and true or false)
      local on = line.index == cur
      r.bg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], on and 0.22 or 0)
    end
    r:Show()
  end
  for n = #lines + 1, #frame.rows do frame.rows[n]:Hide() end
  frame.content:SetHeight(math.max(#lines * ROW_H, ROW_H))
  frame.sf.UpdateScrollBar()
  local left = 0
  for _, e in ipairs(entries) do
    local k = keyOf(e)
    if not posted[k] and not skipped[k] then left = left + 1 end
  end
  frame.count:SetText(#entries == 0 and "" or ("%d to post"):format(left))
  frame.emptyList:SetShown(#entries == 0)
end

local function drawItem()
  local e = entries[cur]
  local f = frame.item
  f:SetShown(e ~= nil)
  frame.none:SetShown(e == nil)
  if not e then return end
  f.icon:SetTexture(ns:ItemIcon(e.id))
  f.name:SetText(ns.ItemName(e.id))
  local bits = { ("%d in your bags"):format(e.count) }
  if e.usual then bits[#bits + 1] = "usual " .. ns.Money(e.usual) end
  if e.rec and e.rec.q then bits[#bits + 1] = ("%d listed at the last scan"):format(e.rec.q) end
  f.sub:SetText(table.concat(bits, " · "))
  if not f.qty:HasFocus() then f.qty:SetText(tostring(e.qty or 0)) end
  f.price:SetValue(e.price)
  f.hours:SetValue(e.hours)
  local dur = HOURS_TO_INDEX[e.hours] or 3
  local deposit = ns.AuctionDeposit and select(1, ns:AuctionDeposit(e.id, math.max(e.qty or 1, 1), dur)) or 0
  local get = e.price and (ns:AfterCut(e.price, ns.neutralAH) * (e.qty or 0)) or nil
  f.get:SetText(get and ns.Money(get) or "-")
  local why = e.why or ""
  if e.price and e.suggested and e.price ~= e.suggested then why = "your price (suggested " .. ns.MoneyPlain(e.suggested) .. ")" end
  f.why:SetText(("%s%s. Deposit %s. |cff9fe8dcRule from: %s.|r"):format(
    why:sub(1, 1):upper(), why:sub(2), ns.MoneyPlain(deposit or 0), e.ruleFrom or "Default"))
  local k = keyOf(e)
  f.post:SetText(pending and "Confirm post" or "Post")
  f.post:SetEnabled(not posted[k] and not skipped[k] and e.price ~= nil and (e.qty or 0) > 0)
  f.posFrom:SetText(("%d of %d"):format(cur, #entries))
  -- The cheapest listings at the last scan (the price ladder each scan saves).
  local lines = {}
  local ladder = e.rec and e.rec.l
  if ladder then
    local prev = 0
    for p, n in ladder:gmatch("(%d+):(%d+)") do
      p, n = tonumber(p), tonumber(n)
      lines[#lines + 1] = ("%s  x%d"):format(ns.Money(p), n - prev)
      prev = n
      if #lines >= 8 then break end
    end
  end
  f.ladder:SetText(#lines > 0 and table.concat(lines, "\n") or "|cff888888No listings saved for it yet: a scan (or Live watch) fills this.|r")
  local when = e.rec and e.rec.t
  f.ladderTitle:SetText(when and ("Cheapest at the last scan (%s)"):format(ns.Age and ns.Age(when) or date("%H:%M", when))
    or "Cheapest at the last scan")
end

refresh = function()
  if not (frame and frame:IsVisible()) then return end
  drawList()
  drawItem()
end

local function build(host)
  frame = CreateFrame("Frame", "ForeverLedgerPost", host)
  frame:SetAllPoints(host)
  frame:EnableMouse(true)
  T:Fill(frame, T.bg)
  frame:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" and scrollPost then
      setScrollPost(false)
      self:SetPropagateKeyboardInput(false)
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)

  -- Left: your bags.
  local listBox = CreateFrame("Frame", nil, frame)
  listBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -40)
  listBox:SetPoint("BOTTOMLEFT", 8, 8)
  listBox:SetWidth(LEFT_W)
  T:Border(listBox)
  -- A glow round the list while Scroll to post is on, as round the Buy queue.
  local glow = listBox:CreateTexture(nil, "BACKGROUND")
  glow:SetPoint("TOPLEFT", -2, 2)
  glow:SetPoint("BOTTOMRIGHT", 2, -2)
  glow:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.18)
  glow:Hide()
  function listBox:SetBackdropShown(on) glow:SetShown(on) end
  frame.listBox = listBox
  frame.sf, frame.content = T:Scroll(listBox)
  frame.sf:SetPoint("TOPLEFT", 2, -2)
  frame.sf:SetPoint("BOTTOMRIGHT", -3, 3)
  local scrollList = frame.sf:GetScript("OnMouseWheel")
  frame.sf:SetScript("OnMouseWheel", function(self, delta)
    if scrollPost then postCurrent() return end
    if scrollList then scrollList(self, delta) end
  end)
  frame.rows = {}
  frame.emptyList = T:Text(listBox, 12, T.dim)
  frame.emptyList:SetPoint("CENTER")
  frame.emptyList:SetWidth(LEFT_W - 30)
  frame.emptyList:SetText("Nothing in your bags to post. Show: Everything lists all you could.")

  -- Above the list: what's shown, how many left, Scroll to post.
  frame.showBtn = T:Button(frame, "Show: Worth posting", 150, function(self)
    frame.showAll = not frame.showAll
    self:SetText(frame.showAll and "Show: Everything" or "Show: Worth posting")
    ns:RefreshPost()
  end, 22)
  frame.showBtn:SetPoint("TOPLEFT", 62, -10)   -- right of the window's portrait
  frame.count = T:Text(frame, 11, T.dim)
  frame.count:SetPoint("LEFT", frame.showBtn, "RIGHT", 10, 0)
  frame.scrollSwitch = T:Check(frame, function(b) setScrollPost(b:GetChecked()) end, "switch")
  frame.scrollSwitch:SetPoint("TOPLEFT", listBox, "TOPRIGHT", -150, 24)
  frame.scrollSwitch.label:SetText("Scroll to post")
  frame.scrollSwitch:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Scroll to post", 1, 1, 1)
    GameTooltip:AddLine("While it's on, each mouse wheel tick over your bag list posts the highlighted item at the price shown, then moves to the next. Off, or Esc: the wheel just scrolls. It starts off every visit. Middle-click a row to skip it.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  frame.scrollSwitch:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Right: the item being posted.
  local f = CreateFrame("Frame", nil, frame)
  f:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 12, 30)
  f:SetPoint("BOTTOMRIGHT", -10, 8)
  frame.item = f
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(32, 32)
  f.icon:SetPoint("TOPLEFT", 0, 0)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.name = T:Text(f, 15)
  f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -1)
  f.name:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.name:SetJustifyH("LEFT")
  f.name:SetWordWrap(false)
  f.sub = T:Text(f, 11, T.dim)
  f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
  f.sub:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.sub:SetJustifyH("LEFT")

  local function label(text, anchor, x)
    local fs = T:Text(f, 10, T.dim)
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, -12)
    fs:SetText(text)
    return fs
  end
  local qtyL = label("How many", f.icon)
  f.qty = T:EditBox(f, 60)
  f.qty:SetPoint("TOPLEFT", qtyL, "BOTTOMLEFT", 0, -3)
  f.qty:SetNumeric(true)
  f.qty:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local e = entries[cur]
    if not e then return end
    local n = math.min(tonumber(self:GetText()) or 0, e.count)
    edits[keyOf(e)] = edits[keyOf(e)] or {}
    edits[keyOf(e)].qty = n
    e.qty = n
    drawItem()
  end)
  f.max = T:Button(f, "Max", 40, function()
    local e = entries[cur]
    if not e then return end
    edits[keyOf(e)] = edits[keyOf(e)] or {}
    edits[keyOf(e)].qty = e.count
    e.qty = e.gear and 1 or e.count
    f.qty:SetText(tostring(e.qty))
    drawItem()
  end, 22)
  f.max:SetPoint("LEFT", f.qty, "RIGHT", 4, 0)

  local priceL = T:Text(f, 10, T.dim)
  priceL:SetPoint("LEFT", qtyL, "LEFT", 130, 0)
  priceL:SetText("Price each")
  f.price = T:MoneyBox(f, function(v)
    local e = entries[cur]
    if not e or not v then return end
    edits[keyOf(e)] = edits[keyOf(e)] or {}
    edits[keyOf(e)].price = v
    e.price = v
    drawList()
    drawItem()
  end)
  f.price:SetPoint("TOPLEFT", priceL, "BOTTOMLEFT", 0, -3)

  local hoursL = T:Text(f, 10, T.dim)
  hoursL:SetPoint("LEFT", priceL, "LEFT", 120, 0)
  hoursL:SetText("How long")
  f.hours = T:Choice(f, { { value = 2, label = "2h" }, { value = 8, label = "8h" }, { value = 24, label = "24h" } }, function(v)
    local e = entries[cur]
    if not e then return end
    edits[keyOf(e)] = edits[keyOf(e)] or {}
    edits[keyOf(e)].hours = v
    e.hours = v
    drawItem()
  end)
  f.hours:SetPoint("TOPLEFT", hoursL, "BOTTOMLEFT", 0, -3)

  local getL = label("You get after the cut", f.qty, 0)
  f.get = T:Text(f, 14, { 0.88, 0.72, 0.35 })
  f.get:SetPoint("TOPLEFT", getL, "BOTTOMLEFT", 0, -3)
  f.why = T:Text(f, 11, T.dim)
  f.why:SetPoint("TOPLEFT", f.get, "BOTTOMLEFT", 0, -8)
  f.why:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.why:SetJustifyH("LEFT")

  f.prev = T:Button(f, "Previous", 80, function() cur = nextUsable(cur, -1); pending = nil; refresh() end)
  f.prev:SetPoint("TOPLEFT", f.why, "BOTTOMLEFT", 0, -10)
  f.skip = T:Button(f, "Skip", 70, function()
    local e = entries[cur]
    if e then skipped[keyOf(e)] = true end
    pending = nil
    cur = nextUsable(cur, 1)
    refresh()
  end)
  f.skip:SetPoint("LEFT", f.prev, "RIGHT", 6, 0)
  f.post = T:Button(f, "Post", 110, postCurrent, 28)
  f.post:SetPoint("TOPRIGHT", f.why, "BOTTOMRIGHT", 0, -8)
  f.posFrom = T:Text(f, 11, T.dim)
  f.posFrom:SetPoint("RIGHT", f.post, "LEFT", -10, 0)
  frame.note = T:Text(f, 11, { 0.62, 0.91, 0.86 })
  frame.note:SetPoint("TOPLEFT", f.prev, "BOTTOMLEFT", 0, -8)
  frame.note:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  frame.note:SetJustifyH("LEFT")

  f.ladderTitle = T:Text(f, 10, T.dim)
  f.ladderTitle:SetPoint("TOPLEFT", frame.note, "BOTTOMLEFT", 0, -12)
  f.ladder = T:Text(f, 11)
  f.ladder:SetPoint("TOPLEFT", f.ladderTitle, "BOTTOMLEFT", 0, -4)
  f.ladder:SetJustifyH("LEFT")
  f.ladder:SetSpacing(2)

  frame.none = T:Text(frame, 12, T.dim)
  frame.none:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 14, -10)
  frame.none:SetText("Pick something on the left.")

  frame:SetScript("OnShow", function()
    setScrollPost(false)
    ns:RefreshPost()
  end)
  frame:SetScript("OnHide", function()
    pending = nil
    setScrollPost(false)
  end)
  frame:SetScript("OnSizeChanged", function() refresh() end)
  frame:Hide()
end

-- The view inside our auction house tab (AHTabs.lua).
function ns:PostFrame(host)
  if not frame and host then build(host) end
  return frame
end

-- New bag contents (posted, bought, looted) while the tab is open.
ns:On("BAG_UPDATE_DELAYED", function()
  if frame and frame:IsVisible() then ns:RefreshPost() end
end)

-- Each visit starts afresh: nothing skipped or posted, Scroll to post off.
ns:On("AUCTION_HOUSE_SHOW", function()
  skipped, posted, edits, pending, cur = {}, {}, {}, nil, 1
  scrollPost = false
end)
ns:On("AUCTION_HOUSE_CLOSED", function()
  pending = nil
  scrollPost = false
end)
