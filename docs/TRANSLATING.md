# Translating Forever Ledger

Forever Ledger is written in English. Each other language is one file in `Locales\`, which the addon loads only on a game client in that language. Anything without a translation shows in English, so a translation can be partial and still useful.

## How it works

- `Locale.lua` is the shared core. It picks the table for the client's language (`GetLocale()`) and translates text as it is shown: windows, buttons, tooltips and chat messages.
- `Locales\<code>.lua` holds one language: its strings, and optionally a font and a few helpers. Simplified Chinese (`Locales\zhCN.lua`) is the example to follow.
- The English text in the code is the key. When the English text changes, its old translation stops matching and the line shows in English until the file gets the new wording.
- `/fl api`, `/fl perf`, `/fl de`, `/fl trainer` and debug lines stay English on purpose, so bug reports read the same from every client.

## Starting a language

1. Copy the top of `Locales\zhCN.lua`: the early return for other clients, the `language` table, and `ns.RegisterLocale` at the end, with your language code (`deDE`, `frFR`, `esES`, `esMX`, `ptBR`, `ruRU`, `koKR`, `zhTW`, `itIT`).
2. Add the file to `ForeverLedger.toc`, right after `Locales\zhCN.lua`.
3. Get every English string to translate:

   ```
   lua5.1 tools/locale-report.lua new
   ```

   Each line comes out as `language.strings["English"] = ""`: fill in the quotes.

## After each release

```
lua5.1 tools/locale-report.lua           how much each language covers
lua5.1 tools/locale-report.lua ruRU      only the strings ruRU has no entry for yet
```

The same summary runs on every push (GitHub Actions, Check code, "Translation coverage"). The report is a guide: it finds quoted text in the code that looks like something a player reads. A sentence built from pieces may need the whole sentence translated, which the report can't see.

## Rules for the strings

- Keep every `%s`, `%d`, `%.1f` and the like, the same number of them in the same order. Word order around them is yours to change.
- Keep color codes (`|cffffd100` ... `|r`), item links and icons exactly as they are.
- Don't translate slash commands (`/fl ...`), setting keys or anything saved.
- Money stays in the game's coin icons where the addon shows them.

## Optional parts of a language file

- `language.font`: a font with your alphabet, if the game's default doesn't cover it.
- `language.FormatElapsed(seconds)`: how "2m 5s" is written.
- `language.TransformVisible(text, whole)`: a last change to visible text (zhCN uses it for units).
- `language.postMarks`: the Post tab's state words, when one English word needs two translations.
- `language.chatWords`: words players use in your language when they ask for a crafter or a class service, for the Customers finder. Lower case:

  ```lua
  language.chatWords = {
    asking = { "ищу", "нужен" },          -- someone looking for help
    offering = { "продам", "крафчу" },    -- a crafter advertising (skipped)
    professions = { Enchanting = { "чант", "энчантер" } },
    services = { mage = { "вода", "еда" }, portal = { "портал" }, summon = { "суммон" }, lockpick = { "взлом" } },
  }
  ```

## What the addon reads from the game

The addon never relies on English game text where an ID exists: professions by skill line, quests by quest ID, riding and Arcane Salvager by spell and item, the Trade channel by its channel number, Waylaid Crates by item, neutral auction houses by map. Names the game itself gives in your language (professions, quests, zones) are used for display without a translation entry. If you see game text that only works in English, please open an issue.
