-- Money as text (Core.lua ns.Money, ns.MoneyPlain) and money typed in (ParseMoney,
-- ParseMoneyLoose). ns.Money shows the game's coin icons; ns.MoneyPlain writes plain
-- "1g 2s 3c" for text boxes.
local T = ...
local ns = T.ns

local ICONS = { g = "Gold", s = "Silver", c = "Copper" }
local function coins(text)
  return (text:gsub("(%d+)([gsc])", function(n, unit)
    return n .. "|TInterface\\MoneyFrame\\UI-" .. ICONS[unit] .. "Icon:0:0:2:0|t"
  end))
end

T.test("Money: the game's gold, silver and copper icons after each number", function()
  T.eq(ns.Money(12345), "1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 23|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
    .. " 45|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
end)

T.test("Money: copper, silver, gold", function()
  T.eq(ns.Money(1), coins("1c"))
  T.eq(ns.Money(75), coins("75c"))
  T.eq(ns.Money(100), coins("1s"))
  T.eq(ns.Money(150), coins("1s 50c"))
  T.eq(ns.Money(10000), coins("1g"))
  T.eq(ns.Money(12345), coins("1g 23s 45c"))
  T.eq(ns.Money(10050), coins("1g 50c"), "no 0s in the middle")
end)

T.test("Money: zero, rounding, big numbers, nil", function()
  T.eq(ns.Money(0), coins("0c"))
  T.eq(ns.Money(0.4), coins("0c"))
  T.eq(ns.Money(99.5), coins("1s"), "rounds to the nearest copper")
  T.eq(ns.Money(123456789), coins("12345g 67s 89c"))
  T.eq(ns.Money(nil), "?")
end)

T.test("MoneyShort: rounded, with coin icons", function()
  T.eq(ns.MoneyShort(12355), coins("1g 24s"))
  T.eq(ns.MoneyShort(nil), "?")
end)

T.test("MoneyPlain", function()
  T.eq(ns.MoneyPlain(0), "0c")
  T.eq(ns.MoneyPlain(nil), "0c")
  T.eq(ns.MoneyPlain(25025), "2g 50s 25c")
  T.eq(ns.MoneyPlain(500000), "50g")
  T.eq(ns.MoneyPlain(9999999), "999g 99s 99c")
end)

T.test("ParseMoney (strict)", function()
  T.eq(ns.ParseMoney("1g50s"), 15000)
  T.eq(ns.ParseMoney("1g 50s 3c"), 15003)
  T.eq(ns.ParseMoney("75"), 75, "a plain number is copper")
  T.eq(ns.ParseMoney("25s"), 2500)
  T.eq(ns.ParseMoney("abc"), nil)
  T.eq(ns.ParseMoney(""), nil)
  T.eq(ns.ParseMoney("5x"), nil)
end)

T.test("ParseMoneyLoose: gold silver copper by spaces or dots", function()
  T.eq(ns.ParseMoneyLoose("2 50 25"), 25025)
  T.eq(ns.ParseMoneyLoose("2.50.25"), 25025)
  T.eq(ns.ParseMoneyLoose("2 50"), 25000, "two numbers are gold and silver")
  T.eq(ns.ParseMoneyLoose("12.50", "g"), 125000)
end)

T.test("ParseMoneyLoose: with units", function()
  T.eq(ns.ParseMoneyLoose("2g 50s"), 25000)
  T.eq(ns.ParseMoneyLoose("2g50s"), 25000)
  T.eq(ns.ParseMoneyLoose("2g 50s 25c"), 25025)
  T.eq(ns.ParseMoneyLoose("75c"), 75)
  T.eq(ns.ParseMoneyLoose("1.5g"), 15000)
  T.eq(ns.ParseMoneyLoose("2,5g"), 25000, "a comma for the decimal point")
  T.eq(ns.ParseMoneyLoose("2.5s"), 250)
  T.eq(ns.ParseMoneyLoose("  3G  "), 30000, "spaces and capitals")
end)

T.test("ParseMoneyLoose: plain numbers in the box's unit", function()
  T.eq(ns.ParseMoneyLoose("12"), 12, "copper by default")
  T.eq(ns.ParseMoneyLoose("12", "s"), 1200)
  T.eq(ns.ParseMoneyLoose("12", "g"), 120000)
end)

T.test("ParseMoneyLoose: off, any and junk", function()
  T.eq(ns.ParseMoneyLoose(""), 0)
  T.eq(ns.ParseMoneyLoose(nil), 0)
  T.eq(ns.ParseMoneyLoose("off"), 0)
  T.eq(ns.ParseMoneyLoose("0"), 0)
  T.eq(ns.ParseMoneyLoose("any"), -1)
  T.eq(ns.ParseMoneyLoose("abc"), nil)
  T.eq(ns.ParseMoneyLoose("2g 50"), nil, "a number without a unit after one with")
  T.eq(ns.ParseMoneyLoose("-5"), nil, "negative")
  T.eq(ns.ParseMoneyLoose("5x"), nil)
end)

-- One digit after a dot is a decimal (owner, October 4): "1.5" is one and a half gold, as
-- "1.5g" is. Two digits, or a space, stay gold and silver.
T.test("ParseMoneyLoose: 1.5 is 1g 50s", function()
  T.eq(ns.ParseMoneyLoose("1.5", "g"), 15000)
  T.eq(ns.ParseMoneyLoose("1.05", "g"), 10500)
  T.eq(ns.ParseMoneyLoose("1 5", "g"), 10500, "a space is gold then silver")
  T.eq(ns.ParseMoneyLoose("1.5.25"), 10525, "three numbers are gold silver copper")
end)

T.test("Money rounded for narrow columns: no copper from 1g, no silver from 100g", function()
  T.eq(ns.MoneyRound(9999), 9999, "under a gold: exact")
  T.eq(ns.MoneyRound(12345), 12300)
  T.eq(ns.MoneyRound(12355), 12400)
  T.eq(ns.MoneyRound(1234567), 1230000)
  T.eq(ns.MoneyRound(nil), nil)
end)

T.test("Money: colored letters when Show money as is set to them", function()
  local saved = ns.db.settings.moneyStyle
  ns.db.settings.moneyStyle = "letters"
  local ok, out = pcall(ns.Money, 12345)
  ns.db.settings.moneyStyle = saved
  T.ok(ok, out)
  T.eq(out, "1|cffffd100g|r 23|cffc7c7cfs|r 45|cffeda55fc|r")
  T.eq(ns.Money(12345), coins("1g 23s 45c"), "back to coins")
end)

T.test("MoneyBrief: two coins from 1 gold, exact under it", function()
  T.eq(ns.MoneyBrief(3297061), coins("329g 71s"), "rounded to the silver")
  T.eq(ns.MoneyBrief(3299961), coins("330g"), "rounding up past a gold")
  T.eq(ns.MoneyBrief(9999), coins("99s 99c"), "under a gold every coin stays")
  T.eq(ns.MoneyBrief(10049), coins("1g"))
  T.eq(ns.MoneyBrief(0), coins("0c"))
  T.eq(ns.MoneyBrief(nil), "?")
end)
