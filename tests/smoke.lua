-- Smoke test of main.lua against stubbed KOReader modules and fake sockets.
-- Run from the repo root:  luajit tests/smoke.lua
package.path = "./?.lua;" .. package.path
math.randomseed(tonumber(os.getenv("SEED")) or 1) -- SEED=n varies who starts

local tmp = os.getenv("TMPDIR") or "/tmp"
local root = tmp .. "/backgammon-smoke-" .. os.time()
os.execute("mkdir -p " .. root .. "/settings")

local shown, notes, toasts = {}, {}, {}
local function stub(name, mod) package.preload[name] = function() return mod end end
local function class(t)
    t = t or {}
    t.extend = function(self, o) o = o or {}; setmetatable(o, { __index = self }); o.extend = t.extend; o.new = t.new; return o end
    t.new = function(self, o)
        o = o or {}
        setmetatable(o, { __index = self })
        if o._init then o:_init() end
        if o.init then o:init() end
        return o
    end
    return t
end
local function sized(h) return class({ getSize = function() return { w = 100, h = h } end, free = function() end }) end

stub("gettext", setmetatable({ current_lang = "C" }, { __call = function(_, s) return s end }))
stub("ffi/util", { template = function(s, ...)
    local a = { ... }
    return (s:gsub("%%(%d)", function(i) return tostring(a[tonumber(i)]) end))
end })
stub("ffi/blitbuffer", setmetatable({}, { __index = function(_, k) return k end }))
stub("datastorage", { getSettingsDir = function() return root .. "/settings" end })
stub("logger", { warn = print, info = function() end, dbg = function() end })
local kindle = false
stub("device", {
    model = "Kindle Test",
    isKindle = function() return kindle end,
    hasKeys = function() return true end,
    input = { group = { Back = "Back" } },
    screen = { getWidth = function() return 600 end, getHeight = function() return 800 end },
})
stub("ui/font", { getFace = function(_, name, size) return { name = name, size = size } end })
stub("ui/geometry", { new = function(_, o) return o end })
stub("ui/gesturerange", class())
stub("ui/size", { padding = { large = 10, default = 5 }, line = { thin = 1 } })
stub("ui/widget/container/widgetcontainer", class())
stub("ui/widget/container/inputcontainer", class({
    _init = function(self) self.key_events = self.key_events or {}; self.ges_events = self.ges_events or {} end,
}))
stub("ui/widget/container/framecontainer", class())
stub("ui/widget/verticalgroup", class())
stub("ui/widget/horizontalgroup", class())
stub("ui/widget/verticalspan", class())
stub("ui/widget/horizontalspan", class())
stub("ui/widget/titlebar", sized(50))
stub("ui/widget/textboxwidget", sized(40))
stub("ui/widget/buttontable", sized(45))
local TextWidget = sized(20)
TextWidget.getFontSizeToFitHeight = function(_, _name, h) return h end
TextWidget.paintTo = function() end
stub("ui/widget/textwidget", TextWidget)
stub("ui/widget/infomessage", class({ init = function(self) table.insert(notes, self.text) end }))
stub("ui/widget/confirmbox", class())
local dialogs = {}
stub("ui/widget/inputdialog", class({
    init = function(self) table.insert(dialogs, self) end,
    onShowKeyboard = function() end,
    getInputText = function(self) return self.text_value or self.input end,
}))
local menus = {}
stub("ui/widget/menu", class({
    init = function(self) table.insert(menus, self) end,
    switchItemTable = function(self, _title, items) self.item_table = items end,
}))
stub("ui/widget/notification", { notify = function(_, text) table.insert(toasts, text) end })
stub("ui/network/manager", { runWhenOnline = function(_, cb) cb() end })
local clock = 0
stub("ui/time", { now = function() return clock end, to_s = function(t) return t end })
local zmqs, standby, closed = {}, 0, {}
local scheduled, dirty = {}, {}
local last_close_refresh
stub("ui/uimanager", {
    show = function(_, w) table.insert(shown, w) end,
    close = function(_, w, refresh)
        last_close_refresh = refresh
        table.insert(closed, w)
        if w and w.onCloseWidget then w:onCloseWidget() end
    end,
    forceRePaint = function() end,
    setDirty = function(_, w, kind, region) table.insert(dirty, { kind = kind, region = region }) end,
    insertZMQ = function(_, z) table.insert(zmqs, z); return z end,
    scheduleIn = function(_, _s, fn) table.insert(scheduled, fn) end,
    removeZMQ = function(_, z) for i = #zmqs, 1, -1 do if zmqs[i] == z then table.remove(zmqs, i) end end end,
    preventStandby = function() standby = standby + 1 end,
    allowStandby = function() standby = standby - 1 end,
})
stub("luasettings", { open = function()
    local data = {}
    return {
        readSetting = function(_, k) return data[k] end,
        saveSetting = function(_, k, v) data[k] = v end,
        isTrue = function(_, k) return data[k] == true end,
        flipNilOrFalse = function(_, k) if data[k] then data[k] = nil else data[k] = true end end,
        flush = function() end,
    }
end })

-- Fake LuaSocket ----------------------------------------------------------------
local function fake_tcp(incoming)
    local s = { sent = "", incoming = incoming or {}, closed = false }
    function s:settimeout() end
    function s:setoption() return true end
    function s:send(data) self.sent = self.sent .. data; return #data end
    function s:receive()
        local chunk = table.remove(self.incoming, 1)
        if chunk == "CLOSE" then return nil, "closed", "" end
        return nil, "timeout", chunk or ""
    end
    function s:close() self.closed = true end
    return s
end
local udps, pending_clients, bind_error = {}, {}, nil
-- the newest UDP socket bound to `port`
local function udp_on(port)
    for i = #udps, 1, -1 do if udps[i].port == port then return udps[i] end end
end
local connect_to
local function fake_udp()
    local u = { out = {}, inbox = {} }
    function u:setsockname(_h, port) self.port = port; return true end
    function u:setpeername() end
    function u:getsockname() return "192.168.1.20" end
    function u:settimeout() end
    function u:setoption() return true end
    function u:sendto(msg, ip, port) table.insert(self.out, { msg, ip, port }) end
    function u:receivefrom()
        local m = table.remove(self.inbox, 1)
        if not m then return nil, "timeout" end
        return m[1], m[2], m[3]
    end
    function u:close() self.closed = true end
    return u
end
local tcps = {}
stub("socket", {
    udp = function() local u = fake_udp(); table.insert(udps, u); return u end,
    tcp = function()
        local s = fake_tcp()
        function s:connect(host, port)
            connect_to = host .. ":" .. port
            if host == "10.0.0.66" then return nil, "connection refused" end
            return 1
        end
        table.insert(tcps, s)
        return s
    end,
    bind = function()
        if bind_error then return nil, bind_error end
        local s = fake_tcp()
        s.accept = function() return table.remove(pending_clients, 1) end
        return s
    end,
})

local passed, failed = 0, 0
local function eq(actual, expected, name)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        print(("FAIL %s\n  expected: %q\n  actual:   %q"):format(name, tostring(expected), tostring(actual)))
    end
end

local function tick(n)
    for _i = 1, n or 1 do
        for _j, z in ipairs({ unpack(zmqs) }) do eq(z.waitEvent(z), nil, "waitEvent returns nil") end
    end
end

-- Finds widgets in the screen's tree.
local function find_all(w, pred, out)
    out = out or {}
    if type(w) ~= "table" then return out end
    if pred(w) then table.insert(out, w) end
    for _i, child in ipairs(w) do find_all(child, pred, out) end
    return out
end
local function buttons(screen)
    local tables = find_all(screen, function(w) return w.buttons ~= nil end)
    local out = {}
    for _i, b in ipairs(tables[1] and tables[1].buttons[1] or {}) do out[b.text] = b end
    return out
end
local function status_of(screen)
    return find_all(screen, function(w) return w.alignment == "center" end)[1].text
end
local function paint(board)
    local calls = 0
    local bb = setmetatable({}, { __index = function() return function() calls = calls + 1 end end })
    board:paintTo(bb, 5, 7)
    return calls
end

local Rules = require("backgammonwifi/rules")
local Backgammon = dofile("main.lua")
local plugin = Backgammon:new{ ui = { menu = { registerToMainMenu = function() end } } }
local menu_items = {}
plugin:addToMainMenu(menu_items)
eq(menu_items.backgammonwifi.text, "Backgammon (Wi-Fi)", "main menu entry")
local function item(id)
    for _i, it in ipairs(menu_items.backgammonwifi.sub_item_table_func()) do
        if it.backgammonwifi_item == id then return it end
    end
end
eq(item("name").text_func(), "Your name: Kindle Test", "default name is the device model")
item("name").callback({ updateItems = function() end })
dialogs[#dialogs].text_value = "  Martin\n "
dialogs[#dialogs].buttons[1][2].callback()
eq(item("name").text_func(), "Your name: Martin", "name saved, cleaned")
item("rules").callback()
eq(notes[#notes]:match("^Each player has 15") ~= nil, true, "rules shown")

-- Hosting ------------------------------------------------------------------------
bind_error = "address already in use"
item("host").callback()
eq(notes[#notes], "Cannot host a game: address already in use", "port taken")
eq(#zmqs, 0, "nothing polled after a failed host")
bind_error = nil

kindle = true
local executed = {}
local real_execute = os.execute
os.execute = function(cmd) table.insert(executed, cmd) end
item("host").callback()
os.execute = real_execute
eq(#executed, 4, "Kindle firewall opened for TCP and discovery")
local screen = shown[#shown]
eq(screen.covers_fullscreen, true, "game screen shown")
eq(#zmqs .. " " .. standby, "1 1", "game polled, standby prevented")
eq(screen.title_bar.subtitle, nil, "no opponent yet")
eq(status_of(screen):match("Your address: 192.168.1.20") ~= nil, true, "host address shown")
eq(screen.board.on_tap, nil, "board not tappable before the game")
eq(paint(screen.board) > 100, true, "board painted")
eq(buttons(screen).Done, nil, "no buttons while waiting")

-- discovery answered while waiting
local hudp = udp_on(7542)
hudp.inbox = { { "DISCOVER 2", "192.168.1.30", 7543 } }
tick()
eq(hudp.out[1] and hudp.out[1][1], "GAME 2 7541 Martin", "discovery answered")

-- runs the roll animation; returns the number of frames
local function animate()
    local frames = 0
    while #scheduled > 0 do
        table.remove(scheduled, 1)()
        frames = frames + 1
    end
    return frames
end

-- a guest joins: the opening roll
local client = fake_tcp({ "HELLO 2 Guest\n" })
table.insert(pending_clients, client)
tick(2)
eq(client.sent, "WELCOME 2 Martin\n", "host welcomes the guest")
eq(screen.title_bar.subtitle, "Opponent: Guest", "opponent shown")
eq(status_of(screen), "Guest joined the game.\nOpening roll: tap Roll or the board. The higher die starts.",
    "opening roll asked for")
client.incoming = { "OPEN 4\n" }
tick()
eq(status_of(screen):match("\nGuest rolled 4.\nOpening roll") ~= nil, true, "the guest's opening die: " .. status_of(screen))
eq(screen.board.dice.peer.values[1], 4, "shown on the left")
eq(paint(screen.board) > 100, true, "board with the opening die painted")
buttons(screen).Roll.callback()
eq(#screen.board.dice.mine.values, 1, "one die rolls")
eq(animate(), 6, "opening roll animated")
local hd = tonumber(client.sent:match("OPEN (%d)\n$"))
eq(hd ~= nil, true, "opening die sent")
local gd = 4
if hd == 4 then
    eq(status_of(screen):match("^Both rolled 4: roll again.\nOpening roll") ~= nil, true, "a tie: " .. status_of(screen))
    screen.board.on_tap(3) -- a tap on the board rolls too
    animate()
    hd = tonumber(client.sent:match("OPEN (%d)\n$"))
    gd = (hd % 6) + 1 -- higher, or 1 against a 6
    client.incoming = { "OPEN " .. gd .. "\n" }
    tick()
end
eq(status_of(screen):match("Opening roll: you " .. hd .. ", Guest " .. gd .. "%.") ~= nil, true,
    "opening roll shown: " .. status_of(screen))
-- a third device is turned away
local extra = fake_tcp()
table.insert(pending_clients, extra)
tick()
eq(extra.sent .. tostring(extra.closed), "ERROR busy\ntrue", "second guest refused")

-- black's moves (the guest's side), the first legal ones
local function guest_moves(position, d1, d2)
    local t = Rules.turn(position, "black", d1, d2)
    while not t:done() do
        local m = t:moves()[1]
        t:play(m.from, m.die)
    end
    return "MOVE " .. table.concat(t:encode(), " ") .. "\n", t.state
end
local position = Rules.new()
if gd > hd then
    eq(screen.board.dice.mine == nil and screen.board.dice.peer ~= nil, true, "the guest's opening dice shown")
    local line
    line, position = guest_moves(position, gd, hd)
    client.incoming = { line }
    tick()
    eq(client.sent:match("ROLL"), nil, "the host's dice wait for a roll")
    eq(status_of(screen):match("^Guest played .*\nYour turn: tap Roll") ~= nil, true, "guest's moves shown: " .. status_of(screen))
    eq(buttons(screen).Roll.enabled, true, "Roll button")
    paint(screen.board)
    screen.board.on_tap(5) -- a tap on the board rolls too
    eq(status_of(screen):match("Rolling…") ~= nil, true, "rolling")
    eq(buttons(screen).Roll.enabled, false, "no second roll while rolling")
    eq(#screen.board.dice.mine.values, 2, "rolling dice shown")
    eq(animate(), 6, "a few animation frames")
    eq(dirty[#dirty - 1].kind .. " " .. dirty[#dirty - 1].region.h, "fast " .. screen.board.dimen.h, "frames refresh the board quickly")
    eq(client.sent:match("ROLL %d %d\n$") ~= nil, true, "ROLL sent after the animation")
    eq(buttons(screen).Done ~= nil, true, "then the dice are played")
end

-- the board's bottom edge: the same with and without buttons, at the screen's bottom
local function board_bottom(scr)
    local y = 0
    for _i, child in ipairs(scr[1][1]) do
        y = y + (child.getSize and child:getSize().h or child.width)
        if child == scr.board then return y end
    end
end
local function content_height(scr)
    local y = 0
    for _i, child in ipairs(scr[1][1]) do y = y + (child.getSize and child:getSize().h or child.width) end
    return y
end
local bottom_with_buttons = board_bottom(screen)

-- our turn: play with taps
local board = screen.board
eq(board.dice.mine ~= nil and board.on_tap ~= nil, true, "our dice, the board is tappable")
eq(buttons(screen).Done.enabled, false, "Done only after playing the dice")
eq(buttons(screen).Undo.enabled, false, "nothing to undo")
local d = board.dice.mine.values
local t = Rules.turn(position, "white", d[1], d[2])
local mv = t:moves()[1]
screen.board.on_tap(mv.from)
eq(screen.selected, mv.from, "tap picks up a checker")
eq(screen.board.targets[mv.to] ~= nil, true, "its targets are framed")
eq(paint(screen.board) > 100, true, "board with a selection painted")
screen.board.on_tap(mv.from)
eq(screen.selected, nil, "second tap puts it back")
screen.board.on_tap(mv.from)
screen.board.on_tap(mv.to)
eq(screen.selected, nil, "checker moved")
eq(buttons(screen).Undo.enabled, true, "Undo after a move")
eq(next(screen.board.dice.mine.used) ~= nil, true, "the used die is greyed")
buttons(screen).Undo.callback()
eq(buttons(screen).Undo.enabled, false, "move taken back")
-- play the whole turn
t = Rules.turn(position, "white", d[1], d[2])
while not t:done() do
    mv = t:moves()[1]
    screen.board.on_tap(mv.from)
    screen.board.on_tap(mv.to)
    t:play(mv.from, mv.die)
end
eq(status_of(screen):match("All dice played") ~= nil, true, "all dice played")
buttons(screen).Done.callback()
eq(client.sent:match("MOVE " .. table.concat(t:encode(), " "):gsub("%-", "%%-") .. "\n$") ~= nil, true, "moves sent: " .. client.sent)
eq(screen.board.on_tap, nil, "not our turn any more")
eq(buttons(screen).Done, nil, "no buttons while the opponent plays")
eq(board_bottom(screen), bottom_with_buttons, "the board stays where it was")
eq(content_height(screen), 800, "the screen is filled to the bottom")
eq(status_of(screen), "Guest is rolling…\nPips: you " .. Rules.pips(t.state, "white") .. ", Guest " .. Rules.pips(t.state, "black"),
    "waiting for the guest")
client.incoming = { "ROLL 3 1\n" }
tick()
eq(status_of(screen):match("^Guest is playing 3–1") ~= nil, true, "the guest's dice shown")
eq(screen.board.dice.mine == nil and screen.board.dice.peer ~= nil, true, "on the left")

-- taps on the painted board map to points
paint(screen.board)
local u = screen.board.unit
local got
screen.board.on_tap = function(p) got = p end
screen.board:onTapBoard(nil, { pos = { x = 5 + 12 * u + 2, y = 7 + screen.board.dimen.h - 2 * u } })
eq(got, 1, "bottom right is point 1")
screen.board:onTapBoard(nil, { pos = { x = 5 + 2, y = 7 + screen.board.label_h + 2 } })
eq(got, 13, "top left is point 13")
screen.board:onTapBoard(nil, { pos = { x = 5 + 6 * u + 2, y = 7 + 2 * u } })
eq(got, Rules.BAR, "the bar")
screen.board:onTapBoard(nil, { pos = { x = 5 + 13 * u + 2, y = 7 + 9 * u } })
eq(got, Rules.OFF, "the tray")

-- with automatic rolling, the dice are rolled when the opponent's move arrives
item("auto_roll").callback()
eq(item("auto_roll").checked_func(), true, "automatic rolling on")
local guest_move
guest_move = guest_moves(t.state, 3, 1)
client.incoming = { guest_move }
tick()
eq(client.sent:match("ROLL %d %d\n$") ~= nil, true, "rolled automatically")
eq(buttons(screen).Done ~= nil, true, "the dice are to be played")
item("auto_roll").callback()

-- the opponent leaves
client.incoming = { "BYE\n" }
tick()
eq(status_of(screen), "Guest left the game.", "opponent left")
eq(buttons(screen)["Close"] ~= nil, true, "only Close left")
executed = {}
os.execute = function(cmd) table.insert(executed, cmd) end
buttons(screen)["Close"].callback()
os.execute = real_execute
kindle = false
eq(#executed == 4 and executed[1]:match("^iptables %-D") ~= nil, true, "firewall closed")
eq(#zmqs .. " " .. standby, "0 0", "polling and standby released")
eq(closed[#closed], screen, "screen closed")
eq(last_close_refresh, "full", "screen below refreshed")

-- Host: a device leaving before HELLO frees the seat -----------------------------
item("host").callback()
screen = shown[#shown]
client = fake_tcp({})
table.insert(pending_clients, client)
tick()
client.incoming = { "CLOSE" }
tick()
eq(screen.title_bar.subtitle, nil, "still waiting for an opponent")
hudp = udp_on(7542)
hudp.inbox = { { "DISCOVER 2", "192.168.1.31", 7543 } }
tick()
eq(#hudp.out, 1, "discovery answered again")
-- protocol error
client = fake_tcp({ "HELLO 99 Old\n" })
table.insert(pending_clients, client)
tick(2)
eq(client.sent, "ERROR version\n", "old version refused")
eq(status_of(screen):match("^The other device has a different version") ~= nil, true, "version error shown")
screen:onClose()
eq(#zmqs, 0, "game ended")

-- Joining by address -----------------------------------------------------------
item("join").callback()
local dialog = dialogs[#dialogs]
dialog.text_value = "not an address!"
dialog.buttons[1][2].callback()
eq(toasts[#toasts], "Invalid address", "invalid address")
dialog.text_value = "10.0.0.66"
dialog.buttons[1][2].callback()
eq(notes[#notes], "Cannot connect to 10.0.0.66: connection refused", "connection refused")
eq(#zmqs, 0, "no game")
item("join").callback()
dialog = dialogs[#dialogs]
eq(dialog.input, "10.0.0.66", "last address remembered")
dialog.text_value = "10.0.0.9:7000"
dialog.buttons[1][2].callback()
eq(connect_to, "10.0.0.9:7000", "connects to the address")
local sock = tcps[#tcps]
eq(sock.sent, "HELLO 2 Martin\n", "guest says hello")
screen = shown[#shown]
eq(status_of(screen):match("Connecting…$") ~= nil, true, "guest waits for WELCOME")
local plugin_auto = item("auto_roll")
plugin_auto.callback() -- the guest rolls automatically
sock.incoming = { "WELCOME 2 Host\n" }
tick()
eq(screen.title_bar.subtitle, "Opponent: Host", "guest joined")
local od = tonumber(sock.sent:match("OPEN (%d)\n$"))
eq(od ~= nil, true, "opening die rolled automatically")
local hostd = od % 6 + 1
sock.incoming = { "OPEN " .. hostd .. "\n" }
tick()
eq(status_of(screen):match("Opening roll: you " .. od .. ", Host " .. hostd .. ". " .. (od > hostd and "You start." or "Host starts.")) ~= nil,
    true, "opening roll: " .. status_of(screen))
plugin_auto.callback()
eq(screen.board.color, "black", "guest plays black")
eq(screen.board.position.points[1], -2, "guest's 24 is point 1")
clock = clock + 6
tick()
eq(sock.sent:match("PING\n$") ~= nil, true, "keepalive")
sock.incoming = { "CLOSE" }
tick()
eq(status_of(screen), "Connection to Host lost.", "guest: connection lost ends the game")
plugin:onSuspend()
eq(#zmqs .. " " .. standby, "0 0", "suspend ends the game")

-- Finding games ------------------------------------------------------------------
item("find").callback()
local menu = menus[#menus]
eq(menu.item_table[1].text, "Searching for games…", "searching")
eq(#zmqs, 1, "search polled")
local sudp = udp_on(7543)
tick()
eq(#sudp.out, 2, "DISCOVER broadcast")
sudp.inbox = { { "GAME 2 7541 Host", "192.168.1.40", 7542 } }
tick()
eq(menu.item_table[1].text .. " " .. menu.item_table[1].mandatory, "Host 192.168.1.40", "game listed")
eq(menu.item_table[2].text, "Join by address…", "join by address below")
clock = clock + 10
tick()
eq(menu.item_table[1].text, "Searching for games…", "silent game dropped")
sudp.inbox = { { "GAME 2 7541 Host", "192.168.1.40", 7542 } }
tick()
menu.item_table[1].callback()
eq(sudp.closed, true, "search stopped when the list closes")
eq(connect_to, "192.168.1.40:7541", "joins the game found")
eq(#zmqs, 1, "only the game polled")
plugin:onExit()
eq(#zmqs .. " " .. standby, "0 0", "exit ends the game")

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
