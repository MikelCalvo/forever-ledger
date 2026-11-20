-- Translation coverage: which English strings in the addon each language file has no entry
-- for, so translators know what to add after a release. Plain Lua 5.1, from the repository root:
--   lua5.1 tools/locale-report.lua              a summary for every language in Locales\
--   lua5.1 tools/locale-report.lua ruRU         that language's missing strings, ready to
--                                               paste into Locales\ruRU.lua (fill in the "")
--   lua5.1 tools/locale-report.lua new          every string, for starting a new language
-- The check is a guide, not exact: it finds quoted text in the code that looks like
-- something a player reads. Debug lines, /fl api and /fl perf stay English and are skipped.
-- Text built from pieces may be translated as a whole sentence instead of each piece.

-- Files that are data or diagnostics, not player text.
local SKIP = {
  ["ClassicRecipes.lua"] = true, ["ClassicCrafts.lua"] = true, ["ForeverCrafts.lua"] = true,
  ["ClassicItems.lua"] = true, ["Probe.lua"] = true, ["Version.lua"] = true, ["Locale.lua"] = true,
  ["LocaleHooks.lua"] = true,
}

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- The files the game loads, in order.
local function addonFiles()
  local list = {}
  for line in io.lines("ForeverLedger.toc") do
    line = line:gsub("\r", ""):gsub("\\", "/")
    if line:match("%.lua$") and not line:match("^Locales/") and not SKIP[line] then list[#list + 1] = line end
  end
  return list
end

-- Quoted strings in Lua source (short strings only; comments and long strings skipped),
-- each with the text of its line.
local ESC = { n = "\n", t = "\t", ["\\"] = "\\", ['"'] = '"', ["'"] = "'", r = "\r", a = "\a", b = "\b", f = "\f", v = "\v" }
local function literals(src)
  local out, i, n = {}, 1, #src
  local lineStart = 1
  while i <= n do
    local c = src:sub(i, i)
    if c == "\n" then
      lineStart = i + 1
      i = i + 1
    elseif c == "-" and src:sub(i, i + 1) == "--" then
      local eq = src:match("^%[(=*)%[", i + 2)
      if eq then
        local close = src:find("]" .. eq .. "]", i, true)
        i = (close or n) + #eq + 2
      else
        local nl = src:find("\n", i, true)
        i = nl or n + 1
      end
    elseif c == "[" and src:match("^%[=*%[", i) then
      local eq = src:match("^%[(=*)%[", i)
      local close = src:find("]" .. eq .. "]", i, true)
      i = (close or n) + #eq + 2
    elseif c == '"' or c == "'" then
      local buf, j = {}, i + 1
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then
          local e = src:sub(j + 1, j + 1)
          local digits = src:match("^%d%d?%d?", j + 1)
          if digits then buf[#buf + 1] = string.char(tonumber(digits)); j = j + 1 + #digits
          else buf[#buf + 1] = ESC[e] or e; j = j + 2 end
        elseif d == c or d == "\n" then
          break
        else
          buf[#buf + 1] = d
          j = j + 1
        end
      end
      local lineEnd = src:find("\n", i, true) or n
      out[#out + 1] = { text = table.concat(buf), line = src:sub(lineStart, lineEnd) }
      i = j + 1
    else
      i = i + 1
    end
  end
  return out
end

-- Looks like something a player reads: words with a space, or a capitalized word; not an
-- identifier, event name, texture path, color code alone or slash command.
local function playerText(s, line)
  if line:find("Debug", 1, true) or line:find("ns.PREFIX", 1, true) then return false end
  if #s < 2 or not s:find("%a%a") then return false end
  if s:find("^Interface[\\/]") or s:find("^Fonts[\\/]") or s:find("%.tga$") or s:find("%.blp$") then return false end
  if s:find("^[%u%d_]+$") or s:find("^[%l%d_]+$") or s:find("^[%a_][%w_]*%.[%w_.]+$") then return false end
  if s:find("^/") then return false end
  if s:find("^|c%x+$") or s:find("^%%[%w%.]+$") then return false end
  return s:find("%a %a") ~= nil or s:find("^%u%l") ~= nil
end

local function englishStrings()
  local seen, list = {}, {}
  for _, file in ipairs(addonFiles()) do
    local src = readFile(file)
    if src then
      for _, l in ipairs(literals(src)) do
        if playerText(l.text, l.line) and not seen[l.text] then
          seen[l.text] = file
          list[#list + 1] = l.text
        end
      end
    end
  end
  table.sort(list)
  return list, seen
end

-- A language file's table, loaded as that client would load it.
local function loadLanguage(code)
  local chunk = loadfile("Locales/" .. code .. ".lua")
  if not chunk then return nil end
  local registered
  local ns = { RegisterLocale = function(name, value) if name == code then registered = value end end }
  local env = setmetatable({ GetLocale = function() return code end }, { __index = _G })
  setfenv(chunk, env)
  local ok, err = pcall(chunk, "ForeverLedger", ns)
  if not ok then io.stderr:write(code .. ": " .. tostring(err) .. "\n"); return nil end
  return registered
end

local function languages()
  local codes = {}
  for line in io.lines("ForeverLedger.toc") do
    local code = line:gsub("\r", ""):match("^Locales[\\/](%a%a%u%u)%.lua$")
    if code then codes[#codes + 1] = code end
  end
  return codes
end

local function quote(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t") .. '"'
end

local english = englishStrings()
local arg1 = arg and arg[1]
if arg1 == "new" then
  for _, s in ipairs(english) do print(("language.strings[%s] = \"\""):format(quote(s))) end
elseif arg1 then
  local lang = loadLanguage(arg1)
  if not lang then print("No language file Locales/" .. arg1 .. ".lua in the .toc, or it didn't load."); os.exit(1) end
  local strings = lang.strings or {}
  print(("-- Strings Locales/%s.lua has no entry for (generated by tools/locale-report.lua):"):format(arg1))
  for _, s in ipairs(english) do
    if strings[s] == nil then print(("language.strings[%s] = \"\""):format(quote(s))) end
  end
else
  print(("Translation coverage: %d English strings found in the addon's files."):format(#english))
  local inSource = {}
  for _, s in ipairs(english) do inSource[s] = true end
  local failed = false
  for _, code in ipairs(languages()) do
    local lang = loadLanguage(code)
    if not lang then failed = true; print("  " .. code .. ": the file didn't load (see the error above)") end
    if lang then
      local strings, have, extra = lang.strings or {}, 0, 0
      for _, s in ipairs(english) do if strings[s] ~= nil then have = have + 1 end end
      for s in pairs(strings) do if not inSource[s] then extra = extra + 1 end end
      print(("  %s: %d of %d (%d%%) have a translation; %d entries are for text not found as written (built from pieces, or changed since)."):format(
        code, have, #english, math.floor(have * 100 / math.max(#english, 1)), extra))
    end
  end
  print("Missing strings for one language: lua5.1 tools/locale-report.lua <code>")
  if failed then os.exit(1) end
end
