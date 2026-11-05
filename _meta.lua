local _ = require("gettext")
-- KOReader's catalog lacks these; Czech is kept here, as _meta.lua can't require the plugin's modules.
local cs = (_.current_lang or ""):match("^cs") ~= nil
return {
    name = "backgammon",
    version = "0.1.0",
    fullname = cs and "Vrchcáby" or _("Backgammon"),
    description = cs and "Vrchcáby (backgammon) pro dva hráče, každý na své čtečce, přes Wi-Fi."
        or _([[Backgammon for two players, each on their own e-reader, over Wi-Fi.]]),
}
