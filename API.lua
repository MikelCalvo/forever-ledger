local _, ns = ...

local api = { version = 1 }

local function record(itemID)
  if type(itemID) ~= "number" or not ns.db or not ns.db.prices or not ns.MarketKey then return end
  local ok, key = pcall(ns.MarketKey)
  local market = ok and ns.db.prices[key]
  return market and market[itemID]
end

local function own(rec)
  return rec and (rec.src == nil or rec.src == "scan" or rec.src == "full")
end

local function levels(rec)
  local out, prev = {}, 0
  for p, c in (rec.l or ""):gmatch("(%d+):(%d+)") do
    p, c = tonumber(p), tonumber(c)
    if c > prev then out[#out + 1] = { price = p, count = c - prev } end
    prev = c
  end
  if #out == 0 and rec.m then out[1] = { price = rec.m, count = rec.q or 1 } end
  return out
end

function api.GetPrice(itemID)
  local rec = record(itemID)
  if not own(rec) then return end
  if rec.none or not rec.m then return nil, nil, 0, rec.t end
  return math.max(rec.a or rec.m, rec.m), rec.m, rec.q or 0, rec.t
end

function api.GetListings(itemID)
  local rec = record(itemID)
  if not own(rec) then return end
  if rec.none or not rec.m then return {}, 0, rec.t end
  return levels(rec), rec.q or 0, rec.t
end

function api.GetCost(itemID, quantity)
  local rec = record(itemID)
  if not own(rec) or type(quantity) ~= "number" or quantity < 1 then return end
  if rec.none or not rec.m then return nil, 0, rec.t end
  local total, got = 0, 0
  for _, level in ipairs(levels(rec)) do
    local take = math.min(level.count, quantity - got)
    total, got = total + take * level.price, got + take
    if got >= quantity then break end
  end
  return total, got, rec.t
end

function api.GetUsualPrice(itemID, window)
  if type(itemID) ~= "number" or not ns.UsualPrice or not ns.db then return end
  if window ~= nil and not (ns.PRICE_WINDOWS and ns.PRICE_WINDOWS[window]) then return end
  local ok, price, points = pcall(ns.UsualPrice, ns, itemID, window or "week")
  if ok and price then return price, points end
end

function api.GetLastFullScan()
  return ns.db and ns.db.lastFullScan
end

ForeverLedgerAPI = api
