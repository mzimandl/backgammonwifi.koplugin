local _ = require("gettext")
-- KOReader's catalog lacks these; Czech is kept here, as _meta.lua can't require the plugin's modules.
local cs = (_.current_lang or ""):match("^cs") ~= nil
return {
    name = "backgammonwifi",
    version = "0.2.3",
    fullname = cs and "Vrchcáby" or _("Backgammon (Wi-Fi)"),
    description = cs and "Vrchcáby (backgammon) pro dva hráče, každý na své čtečce, přes Wi-Fi."
        or _([[Backgammon for two players, each on their own e-reader, over Wi-Fi.]]),
}
