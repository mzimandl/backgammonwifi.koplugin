--[[--
Backgammon plugin: the board game for two players, each on their own
e-reader, over Wi-Fi. One device hosts the game, the other joins it, either by
address or by finding it on the local network (UDP broadcast).

@module koplugin.Backgammon
]]

-- Own modules must be required at load time: PluginLoader only adds the
-- plugin folder to package.path while main.lua is being loaded.
local L10n = require("backgammon/l10n")
local Match = require("backgammon/match")
local Net = require("backgammon/net")
local Protocol = require("backgammon/protocol")
local Rules = require("backgammon/rules")

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local Screen = Device.screen
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local time = require("ui/time")
local gettext = require("gettext")
-- The plugin's strings are not in KOReader's catalog: its own catalog for
-- KOReader's language first (backgammon/l10n/<lang>.lua, required now, see above).
local _ = L10n.wrap(gettext, L10n.catalog(gettext.current_lang, function(name)
    local ok, catalog = pcall(require, "backgammon/l10n/" .. name)
    return ok and catalog or nil
end))
local T = require("ffi/util").template

local Backgammon = WidgetContainer:extend{
    name = "backgammon",
    is_doc_only = false,
}

local PING_INTERVAL = 5    -- seconds
local PEER_TIMEOUT = 30    -- seconds without any message → connection lost
local CONNECT_TIMEOUT = 5  -- seconds, blocks the UI
local SEARCH_INTERVAL = 1  -- seconds between DISCOVER broadcasts
local SEARCH_EXPIRE = 5    -- seconds: games not heard of are dropped from the list

local function now()
    return time.to_s(time.now())
end

local function notify(text)
    Notification:notify(text)
end

-- The running game and the game search. Module-level, not on the plugin
-- instance: KOReader makes a new instance for every reader/file manager.
-- game: { role, match, conn, host, ip, screen, zmq, message, lost, last_ping, rules }
local game = {}
-- finder: { search, menu, zmq, last_sent, rules }
local finder = {}

-- Kindle firewall --------------------------------------------------------------

local function host_rules(port)
    return {
        string.format("INPUT -p tcp --dport %d -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT", port),
        string.format("OUTPUT -p tcp --sport %d -m conntrack --ctstate ESTABLISHED -j ACCEPT", port),
        string.format("INPUT -p udp --dport %d -j ACCEPT", Protocol.DISCOVERY_PORT),
        string.format("OUTPUT -p udp --sport %d -j ACCEPT", Protocol.DISCOVERY_PORT),
    }
end

local function guest_rules(port)
    return {
        string.format("OUTPUT -p tcp --dport %d -j ACCEPT", port),
        string.format("INPUT -p tcp --sport %d -m conntrack --ctstate ESTABLISHED -j ACCEPT", port),
    }
end

local function search_rules()
    return {
        string.format("INPUT -p udp --dport %d -j ACCEPT", Protocol.SEARCH_PORT),
        string.format("OUTPUT -p udp --sport %d -j ACCEPT", Protocol.SEARCH_PORT),
        string.format("OUTPUT -p udp --dport %d -j ACCEPT", Protocol.DISCOVERY_PORT),
    }
end

-- Opens (op "-A") or closes ("-D") ports in the Kindle firewall (as httpinspector does).
local function kindle_firewall(op, rules)
    if not rules or not Device:isKindle() then return end
    for _i, rule in ipairs(rules) do os.execute("iptables " .. op .. " " .. rule) end
end

-- Polling: UIManager calls a ZMQ's waitEvent() about every 50 ms; it must
-- return nil (anything else is treated as an input event).
local function poller(fn, name)
    return UIManager:insertZMQ({ waitEvent = function()
        local ok, err = pcall(fn)
        if not ok then logger.warn("Backgammon:", name, err) end
        return nil
    end })
end

-- Board widget -----------------------------------------------------------------

-- The board is 14 units wide: points of the left half in columns 0-5, the bar
-- in column 6, the right half in 7-12, borne-off checkers in 13. Seen from the
-- player's side: their home board (points 1-6) bottom right, 7-12 bottom left,
-- 13-18 top left, 19-24 top right; their checkers move counter-clockwise.
local BAR_COL, OFF_COL, COLS = 6, 13, 14
local STACK = 5 -- checkers drawn on a point; more are counted

--- Column and half (true = top) of the player's point `rel` (1..24).
local function point_place(rel)
    if rel <= 6 then return 13 - rel, false end
    if rel <= 12 then return 12 - rel, false end
    if rel <= 18 then return rel - 13, true end
    return rel - 12, true
end

--- The player's point (1..24, Rules.BAR or Rules.OFF) at a column and half.
local function place_point(col, top)
    if col == BAR_COL then return Rules.BAR end
    if col == OFF_COL then return Rules.OFF end
    if top then return col < BAR_COL and col + 13 or col + 12 end
    return col < BAR_COL and 12 - col or 13 - col
end

local PIPS = {
    { { 0, 0 } },
    { { -1, -1 }, { 1, 1 } },
    { { -1, -1 }, { 0, 0 }, { 1, 1 } },
    { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } },
    { { -1, -1 }, { 1, -1 }, { 0, 0 }, { -1, 1 }, { 1, 1 } },
    { { -1, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 1, 1 } },
}

local font_sizes = {} -- unit → label font size

--- The board from `color`'s side.
-- position: Rules position; selected: the player's point whose checker is
-- picked up; targets: { [point] = true } where it can go (Rules.OFF too);
-- landed: { [point] = true } where the opponent's last moves ended;
-- dice = { values, used = { [i] = true }, mine = bool }; on_tap(point).
local BoardWidget = InputContainer:extend{
    width = nil,
    height = nil,
    color = "white",
    position = nil,
    selected = nil,
    targets = nil,
    landed = nil,
    dice = nil,
    on_tap = nil,
}

function BoardWidget:init()
    self.unit = math.floor(math.min(self.width / COLS, self.height / 12.2))
    local u = self.unit
    self.label_h = math.floor(u * 0.6)
    self.dimen = Geom:new{ x = 0, y = 0, w = u * COLS, h = 11 * u + 2 * self.label_h }
    self.line = math.max(1, math.floor(u / 25))
    local fs = font_sizes[u]
    if not fs then
        fs = TextWidget:getFontSizeToFitHeight("cfont", self.label_h, 0)
        font_sizes[u] = fs
    end
    self.face = Font:getFace("cfont", fs)
    self.labels = {}
    for rel = 1, 24 do
        self.labels[rel] = TextWidget:new{ text = tostring(rel), face = self.face, padding = 0 }
    end
    if self.on_tap then
        self.ges_events = {
            TapBoard = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        }
    end
end

function BoardWidget:getSize()
    return Geom:new{ w = self.dimen.w, h = self.dimen.h }
end

function BoardWidget:onTapBoard(_args, ges)
    local u = self.unit
    local col = math.floor((ges.pos.x - self.dimen.x) / u)
    if col < 0 or col >= COLS then return true end
    local top = ges.pos.y - self.dimen.y < self.label_h + 5.5 * u
    self.on_tap(place_point(col, top))
    return true
end

local function paint_centered(bb, widget, x, y, w, h)
    local size = widget:getSize()
    widget:paintTo(bb, x + math.floor((w - size.w) / 2), y + math.floor((h - size.h) / 2))
end

function BoardWidget:paintChecker(bb, cx, cy, color, picked)
    local r = math.floor(self.unit / 2) - 1
    if color == "white" then
        bb:paintCircle(cx, cy, r, picked and Blitbuffer.COLOR_GRAY_9 or Blitbuffer.COLOR_WHITE)
        bb:paintCircle(cx, cy, r, Blitbuffer.COLOR_BLACK, math.max(2, self.line * 2))
    else
        bb:paintCircle(cx, cy, r, Blitbuffer.COLOR_BLACK)
        if picked then bb:paintCircle(cx, cy, math.floor(r * 0.6), Blitbuffer.COLOR_GRAY_9) end
    end
end

--- n checkers of `color` from (cx, y0) going down (dir 1) or up (dir -1).
function BoardWidget:paintStack(bb, cx, y0, dir, n, color, picked)
    local u = self.unit
    local shown = math.min(n, STACK)
    for k = 0, shown - 1 do
        local cy = y0 + dir * (math.floor(u / 2) + k * u)
        self:paintChecker(bb, cx, cy, color, picked and k == shown - 1)
        if k == shown - 1 and n > STACK then
            local count = TextWidget:new{
                text = tostring(n), face = self.face, padding = 0,
                fgcolor = color == "white" and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            }
            paint_centered(bb, count, cx - math.floor(u / 2), cy - math.floor(u / 2), u, u)
            count:free()
        end
    end
end

function BoardWidget:paintTriangle(bb, x, y, top, color)
    local u = self.unit
    local h = math.floor(u * 4.6)
    for i = 0, h - 1 do
        local w = math.floor(u * (h - i) / h)
        local yy = top and y + i or y + 5 * u - 1 - i
        bb:paintRect(x + math.floor((u - w) / 2), yy, w, 1, color)
    end
end

function BoardWidget:paintDie(bb, cx, cy, value, used)
    local s = math.floor(self.unit * 0.8)
    local x, y = cx - math.floor(s / 2), cy - math.floor(s / 2)
    bb:paintRect(x, y, s, s, used and Blitbuffer.COLOR_GRAY_D or Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x, y, s, s, math.max(1, self.line * 2), Blitbuffer.COLOR_BLACK)
    local step, r = math.floor(s * 0.27), math.max(1, math.floor(s / 11))
    for _i, p in ipairs(PIPS[value]) do
        bb:paintCircle(cx + p[1] * step, cy + p[2] * step, r,
            used and Blitbuffer.COLOR_GRAY_7 or Blitbuffer.COLOR_BLACK)
    end
end

function BoardWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local u, lh = self.unit, self.label_h
    local s, me = self.position, self.color
    local opp = Rules.other(me)
    local y_top, y_mid = y + lh, y + lh + 5 * u
    local y_bot = y_mid + u
    local half = math.floor(u / 2)
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    bb:paintRect(x + BAR_COL * u, y_top, u, 11 * u, Blitbuffer.COLOR_GRAY_E)

    for rel = 1, 24 do
        local col, top = point_place(rel)
        local px = x + col * u
        local py = top and y_top or y_bot
        self:paintTriangle(bb, px, py, top, (col + (top and 0 or 1)) % 2 == 0
            and Blitbuffer.COLOR_GRAY_9 or Blitbuffer.COLOR_GRAY_D)
        paint_centered(bb, self.labels[rel], px, top and y or y_bot + 5 * u, u, lh)
        if self.landed and self.landed[rel] then
            bb:paintRect(px + math.floor(u * 0.2), top and y or y_bot + 5 * u + lh - math.max(2, math.floor(u / 10)),
                math.floor(u * 0.6), math.max(2, math.floor(u / 10)), Blitbuffer.COLOR_BLACK)
        end
        local mine, theirs = Rules.count(s, me, rel), Rules.opponent(s, me, rel)
        local n, color = mine, me
        if theirs > 0 then n, color = theirs, opp end
        if n > 0 then
            self:paintStack(bb, px + half, top and y_top or y_bot + 5 * u, top and 1 or -1, n, color,
                self.selected == rel)
        end
        if self.targets and self.targets[rel] then
            bb:paintBorder(px, py, u, 5 * u, math.max(3, math.floor(u / 8)), Blitbuffer.COLOR_BLACK)
        end
    end

    -- bar: own checkers below the middle, the opponent's above it
    local bx = x + BAR_COL * u + half
    if s.bar[me] > 0 then self:paintStack(bb, bx, y_bot, 1, s.bar[me], me, self.selected == Rules.BAR) end
    if s.bar[opp] > 0 then self:paintStack(bb, bx, y_mid, -1, s.bar[opp], opp) end

    -- borne off: own at the bottom, the opponent's at the top
    local ox = x + OFF_COL * u
    local slice = math.floor(5 * u / Rules.CHECKERS)
    local inset = math.floor(u / 8)
    for _i, side in ipairs({ { me, false }, { opp, true } }) do
        local color, top = side[1], side[2]
        for k = 0, s.off[color] - 1 do
            local sy = top and y_top + k * slice or y_bot + 5 * u - (k + 1) * slice
            bb:paintRect(ox + inset, sy, u - 2 * inset, slice,
                color == "white" and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK)
            bb:paintBorder(ox + inset, sy, u - 2 * inset, slice, 1, Blitbuffer.COLOR_BLACK)
        end
    end
    if self.targets and self.targets[Rules.OFF] then
        bb:paintBorder(ox, y_bot, u, 5 * u, math.max(3, math.floor(u / 8)), Blitbuffer.COLOR_BLACK)
    end

    -- frame: both halves and the tray
    local w = self.line * 2
    bb:paintBorder(x, y_top, BAR_COL * u, 11 * u, w, Blitbuffer.COLOR_BLACK)
    bb:paintBorder(x + (BAR_COL + 1) * u, y_top, BAR_COL * u, 11 * u, w, Blitbuffer.COLOR_BLACK)
    bb:paintBorder(ox, y_top, u, 11 * u, w, Blitbuffer.COLOR_BLACK)

    -- dice in the middle: own on the right half, the opponent's on the left
    if self.dice then
        local values = self.dice.values
        local cx0 = x + (self.dice.mine and 10 or 3) * u
        local first = cx0 - math.floor((#values - 1) * u / 2)
        for i, v in ipairs(values) do
            self:paintDie(bb, first + (i - 1) * u, y_mid + half, v, self.dice.used and self.dice.used[i])
        end
    end
end

function BoardWidget:onCloseWidget()
    for rel = 1, 24 do self.labels[rel]:free() end
end

-- Game screen ------------------------------------------------------------------

local GameScreen = InputContainer:extend{
    covers_fullscreen = true,
    selected = nil, -- the player's point whose checker is picked up
}

function GameScreen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:build()
end

local function dice_text(dice)
    return dice[1] .. "–" .. dice[2]
end

--- Legal moves from the selected point: { [to] = move } (smallest die first).
function GameScreen:targets()
    local m = game.match
    if not self.selected or not m:my_turn() then return nil end
    local out
    for _i, mv in ipairs(m.current:moves()) do
        if mv.from == self.selected and (not out or not out[mv.to] or mv.die < out[mv.to].die) then
            out = out or {}
            out[mv.to] = mv
        end
    end
    return out
end

function GameScreen:statusText()
    local m = game.match
    local lines = {}
    if game.message then lines[#lines + 1] = game.message end
    if game.lost then
        -- message says why
    elseif m.phase == "waiting" then
        if m.peer then
            lines[#lines + 1] = T(_("Waiting for %1…"), m.peer)
        elseif game.role == "host" then
            lines[#lines + 1] = game.ip and T(_("Waiting for an opponent. Your address: %1"), game.ip)
                or _("Waiting for an opponent.")
        else
            lines[#lines + 1] = _("Connecting…")
        end
    elseif m.phase == "playing" then
        if m:my_turn() then
            local t = m.current
            if t.max == 0 then
                lines[#lines + 1] = T(_("You rolled %1: no move possible. Tap Done."), dice_text(m.dice))
            elseif t:done() then
                lines[#lines + 1] = _("All dice played. Tap Done, or Undo to take a move back.")
            elseif self.selected then
                lines[#lines + 1] = _("Tap a framed point to move the checker there, or another checker.")
            else
                lines[#lines + 1] = T(_("Your turn (%1): tap a checker to move."), dice_text(m.dice))
            end
        elseif m.dice then
            lines[#lines + 1] = T(_("%1 is playing %2…"), m.peer, dice_text(m.dice))
        else
            lines[#lines + 1] = T(_("%1 is rolling…"), m.peer)
        end
        local s = m:shown()
        lines[#lines + 1] = T(_("Pips: you %1, %2 %3"), Rules.pips(s, m.color), m.peer, Rules.pips(s, m.peer_color))
    else
        lines[#lines + 1] = m.winner == "me" and _("You won!") or T(_("%1 won."), m.peer)
        if m.rematch and not m.peer_rematch then
            lines[#lines + 1] = T(_("Waiting for %1…"), m.peer)
        elseif m.peer_rematch and not m.rematch then
            lines[#lines + 1] = T(_("%1 wants to play again."), m.peer)
        end
    end
    return table.concat(lines, "\n")
end

function GameScreen:buttonRow()
    local m = game.match
    local close = { text = _("Close"), callback = function() self:onClose() end }
    if game.lost then return { close } end
    if m:my_turn() then
        return {
            { text = _("Undo"), enabled = #m.current.played > 0, callback = function()
                m:undo()
                self.selected = nil
                self:update()
            end },
            { text = _("Done"), enabled = m.current:done(), callback = function()
                self.selected = nil
                local ev = m:finish_turn()
                if ev then Backgammon.onGameEvent(ev) end
            end },
        }
    elseif m.phase == "over" then
        return {
            { text = _("Play again"), enabled = not m.rematch, callback = function()
                local ev = m:request_rematch()
                if ev then Backgammon.onGameEvent(ev) else self:update() end
            end },
            close,
        }
    end
end

--- Picks up a checker, or moves the picked-up one to `point`.
function GameScreen:onPointTap(point)
    local m = game.match
    if not m:my_turn() then return end
    local targets = self:targets()
    if targets and targets[point] then
        local mv = targets[point]
        m:play(mv.from, mv.die)
        self.selected = nil
    elseif point == self.selected then
        self.selected = nil
    else
        local movable = false
        for _i, mv in ipairs(m.current:moves()) do
            if mv.from == point then movable = true end
        end
        if movable then
            self.selected = point
        elseif self.selected then
            notify(_("The checker cannot move there."))
            self.selected = nil
        elseif Rules.count(m:shown(), m.color, point) > 0 or point == Rules.BAR then
            notify(m:shown().bar[m.color] > 0 and _("Enter your checkers from the bar first.")
                or _("This checker cannot move."))
        end
    end
    self:update()
end

function GameScreen:build()
    local w, h = self.dimen.w, self.dimen.h
    local m = game.match
    local pad = Size.padding.large
    local inner_w = w - 2 * pad
    local subtitle
    if m.peer then
        subtitle = (m.score.me + m.score.peer > 0)
            and T(_("Opponent: %1 · games %2 : %3"), m.peer, m.score.me, m.score.peer)
            or T(_("Opponent: %1"), m.peer)
    end
    self.title_bar = TitleBar:new{
        width = w,
        fullscreen = true,
        title = _("Backgammon"),
        subtitle = subtitle,
        with_bottom_line = true,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    -- a single movable point (the bar, mostly) is picked up at once
    if m:my_turn() and not self.selected then
        local from
        for _i, mv in ipairs(m.current:moves()) do
            if from and mv.from ~= from then from = false; break end
            from = mv.from
        end
        if from == Rules.BAR then self.selected = from end
    end
    local status = TextBoxWidget:new{
        text = self:statusText(),
        face = Font:getFace("cfont", 18),
        width = inner_w,
        alignment = "center",
    }
    local row = self:buttonRow()
    local buttons = row and ButtonTable:new{ width = inner_w, buttons = { row }, show_parent = self }
    local used = self.title_bar:getSize().h + status:getSize().h + 3 * pad
        + (buttons and buttons:getSize().h + pad or 0)

    local dice
    if m:my_turn() then
        local left, used_dice = {}, {}
        for _i, d in ipairs(m.current.dice) do left[d] = (left[d] or 0) + 1 end
        for i, d in ipairs(m.current.all) do
            if (left[d] or 0) > 0 then left[d] = left[d] - 1 else used_dice[i] = true end
        end
        dice = { values = m.current.all, used = used_dice, mine = true }
    elseif m.phase == "playing" and m.dice then
        dice = { values = m.dice, mine = false }
    end
    local landed
    if m.last_peer_moves then
        landed = {}
        for _i, mv in ipairs(m.last_peer_moves) do
            if mv.to > 0 then landed[25 - mv.to] = true end
        end
    end
    local board = BoardWidget:new{
        width = inner_w,
        height = h - used,
        color = m.color,
        position = m:shown(),
        selected = self.selected,
        targets = self:targets(),
        landed = landed,
        dice = dice,
        on_tap = m:my_turn() and not game.lost and function(point) self:onPointTap(point) end or nil,
    }
    self.board = board

    local content = VerticalGroup:new{
        align = "center",
        self.title_bar,
        VerticalSpan:new{ width = pad },
        status,
        VerticalSpan:new{ width = pad },
        board,
        VerticalSpan:new{ width = pad },
    }
    if buttons then table.insert(content, buttons) end
    self[1] = FrameContainer:new{
        width = w,
        height = h,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
end

function GameScreen:update()
    self:build()
    UIManager:setDirty(self, "ui")
end

function GameScreen:onClose()
    local m = game.match
    local idle = game.lost or m.phase == "over" or not m.peer
    if idle then
        Backgammon.endGame()
    else
        UIManager:show(ConfirmBox:new{
            text = _("Leave the game?"),
            ok_text = _("Leave"),
            ok_callback = function() Backgammon.endGame() end,
        })
    end
    return true
end

-- Running a game ---------------------------------------------------------------

local ERRORS = {
    version = _("The other device has a different version of Backgammon."),
    busy = _("This game already has two players."),
}

function Backgammon.endGame()
    if game.conn then
        if game.match and game.match.peer then game.match:bye() end
        game.conn:close()
    end
    if game.host then game.host:close() end
    if game.zmq then
        UIManager:removeZMQ(game.zmq)
        UIManager:allowStandby()
    end
    kindle_firewall("-D", game.rules)
    local screen = game.screen
    game = {}
    -- the screen covers everything: without a refresh type the display would keep showing it
    if screen then UIManager:close(screen, "full") end
end

--- The connection ended: `reason` = "left" (BYE), an ERRORS key, or a socket error.
local function connection_lost(reason)
    if game.conn then game.conn:close() end
    game.conn = nil
    local m = game.match
    local who = m.peer or _("The opponent")
    if game.role == "host" and m.phase == "waiting" and m.score.me + m.score.peer == 0 and not ERRORS[reason] then
        -- no game played yet: wait for someone else
        if m.peer then game.message = T(_("%1 left."), who) end
        m:drop_peer()
    else
        game.lost = true
        if ERRORS[reason] then game.message = ERRORS[reason]
        elseif reason == "left" then game.message = T(_("%1 left the game."), who)
        else game.message = m.peer and T(_("Connection to %1 lost."), who) or _("Connection lost.") end
        if game.host then game.host:close(); game.host = nil end
    end
    if game.screen then
        game.screen.selected = nil
        game.screen:update()
    end
end

--- The opponent's moves from our side: "bar/22 13/7* 3/off".
local function moves_text(moves)
    local out = {}
    for _i, mv in ipairs(moves) do
        local from = mv.from == Rules.BAR and _("bar") or tostring(25 - mv.from)
        local to = mv.to == Rules.OFF and _("off") or tostring(25 - mv.to)
        out[#out + 1] = from .. "/" .. to .. (mv.hit and "*" or "")
    end
    return table.concat(out, " ")
end

--- Updates the screen after a match event (see backgammon/match.lua).
function Backgammon.onGameEvent(ev)
    local m = game.match
    local t = ev.type
    if t == "joined" then
        game.message = game.role == "host" and T(_("%1 joined the game."), ev.name)
            or T(_("You joined %1's game."), ev.name)
        if ev.start then
            local joined = game.message
            Backgammon.onGameEvent(ev.start)
            game.message = joined .. "\n" .. game.message
        end
    elseif t == "start" then
        local mine, theirs = ev.host_die, ev.guest_die
        if game.role == "guest" then mine, theirs = theirs, mine end
        local roll = T(_("Opening roll: you %1, %2 %3."), mine, m.peer, theirs)
        local who = ev.turn == "me" and _("You start.") or T(_("%1 starts."), m.peer)
        game.message = roll .. " " .. who
    elseif t == "moved" then
        local text = #ev.moves > 0 and T(_("%1 played %2."), m.peer, moves_text(ev.moves))
            or T(_("%1 cannot move."), m.peer)
        local hits = 0
        for _i, mv in ipairs(ev.moves) do if mv.hit then hits = hits + 1 end end
        if hits > 0 then text = text .. " " .. T(_("Your checkers hit: %1."), hits) end
        game.message = text
    elseif t == "played" then
        game.message = nil
    elseif t == "rematch" then
        game.message = _("New game.")
    elseif t == "left" then
        connection_lost("left")
        return
    end
    if game.screen then game.screen:update() end
end

local function poll_game()
    local t = now()
    if game.host then
        local client = game.host:accept()
        if client then
            if game.conn then
                client:settimeout(1)
                client:send(Protocol.line("ERROR", "busy"))
                client:close()
            else
                game.conn = Net.connection(client, t)
                game.last_ping = t
            end
        end
        game.host:answer(not game.conn and game.match.name or nil)
    end
    local conn = game.conn
    if not conn then return end
    local lines, err = conn:poll(t)
    for _i, line in ipairs(lines or {}) do
        local ev, perr = game.match:receive(line)
        if perr then
            logger.warn("Backgammon: protocol error", perr, line)
            if not ERRORS[perr] then conn:send(Protocol.line("ERROR", "protocol")) end
            connection_lost(perr)
            return
        end
        if ev then Backgammon.onGameEvent(ev) end
        if game.conn ~= conn then return end -- the event ended the connection
    end
    if not lines then
        connection_lost(err)
    elseif t - conn.last_seen > PEER_TIMEOUT then
        connection_lost("timeout")
    elseif t - (game.last_ping or 0) >= PING_INTERVAL then
        game.last_ping = t
        game.match:ping()
    end
end

function Backgammon:startGame(role, fields)
    game = fields
    game.role = role
    game.match = Match.new{
        role = role,
        name = self:playerName(),
        send = function(line) if game.conn then game.conn:send(line) end end,
    }
    game.last_ping = now()
    game.zmq = poller(poll_game, "game")
    UIManager:preventStandby()
    game.screen = GameScreen:new{}
    UIManager:show(game.screen)
end

function Backgammon:hostGame()
    NetworkMgr:runWhenOnline(function()
        Backgammon.endGame()
        local socket = require("socket")
        local host, err = Net.host(socket, Protocol.PORT)
        if not host then
            UIManager:show(InfoMessage:new{ text = T(_("Cannot host a game: %1"), tostring(err)) })
            return
        end
        local rules = host_rules(Protocol.PORT)
        kindle_firewall("-A", rules)
        self:startGame("host", { host = host, ip = Net.local_ip(socket), rules = rules })
    end)
end

function Backgammon:joinGame(ip, port)
    NetworkMgr:runWhenOnline(function()
        Backgammon.endGame()
        local socket = require("socket")
        local rules = guest_rules(port)
        kindle_firewall("-A", rules)
        local msg = InfoMessage:new{ text = T(_("Connecting to %1…"), ip) }
        UIManager:show(msg)
        UIManager:forceRePaint()
        local conn, err = Net.connect(socket, ip, port, CONNECT_TIMEOUT, now())
        UIManager:close(msg)
        if not conn then
            kindle_firewall("-D", rules)
            UIManager:show(InfoMessage:new{ text = T(_("Cannot connect to %1: %2"), ip, tostring(err)) })
            return
        end
        self:startGame("guest", { conn = conn, rules = rules })
        game.match:hello()
    end)
end

function Backgammon:joinByAddress()
    local dialog
    dialog = InputDialog:new{
        title = _("Join by address"),
        input = self.settings:readSetting("last_address") or "",
        input_hint = "192.168.1.10",
        description = _("The address is shown on the host's screen."),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Join"), is_enter_default = true, callback = function()
                local text = dialog:getInputText()
                local ip, port = Protocol.parse_address(text)
                if not ip then
                    notify(_("Invalid address"))
                    return
                end
                UIManager:close(dialog)
                self.settings:saveSetting("last_address", text)
                self.settings:flush()
                self:joinGame(ip, port)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- Finding games ----------------------------------------------------------------

local function stop_finder()
    if finder.zmq then UIManager:removeZMQ(finder.zmq) end
    if finder.search then finder.search:close() end
    kindle_firewall("-D", finder.rules)
    finder = {}
end

function Backgammon:finderItems()
    local items = {}
    for _i, g in ipairs(finder.search and finder.search.games or {}) do
        table.insert(items, {
            text = g.name ~= "" and g.name or g.ip,
            mandatory = g.ip,
            callback = function()
                local ip, port = g.ip, g.port
                UIManager:close(finder.menu)
                self:joinGame(ip, port)
            end,
        })
    end
    if #items == 0 then
        table.insert(items, { text = _("Searching for games…"), dim = true, callback = function() end })
    end
    items[#items].separator = true
    table.insert(items, { text = _("Join by address…"), callback = function()
        UIManager:close(finder.menu)
        self:joinByAddress()
    end })
    return items
end

local function poll_finder(plugin)
    local t = now()
    if t - finder.last_sent >= SEARCH_INTERVAL then
        finder.last_sent = t
        finder.search:send()
    end
    local changed = finder.search:poll(t)
    changed = finder.search:expire(t, SEARCH_EXPIRE) or changed
    if changed and finder.menu then
        finder.menu:switchItemTable(nil, plugin:finderItems())
    end
end

function Backgammon:findGames()
    NetworkMgr:runWhenOnline(function()
        stop_finder()
        local socket = require("socket")
        local search, err = Net.search(socket, Net.local_ip(socket))
        if not search then
            UIManager:show(InfoMessage:new{ text = T(_("Cannot search for games: %1"), tostring(err)) })
            return
        end
        finder = { search = search, last_sent = 0, rules = search_rules() }
        kindle_firewall("-A", finder.rules)
        local menu = Menu:new{
            title = _("Find a game"),
            item_table = self:finderItems(),
            covers_fullscreen = true,
            is_borderless = true,
            is_popout = false,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
        }
        local on_close = menu.onCloseWidget
        menu.onCloseWidget = function(m)
            stop_finder()
            if on_close then return on_close(m) end
        end
        finder.menu = menu
        finder.zmq = poller(function() poll_finder(self) end, "search")
        UIManager:show(menu)
    end)
end

-- Plugin -----------------------------------------------------------------------

function Backgammon:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/backgammon.lua")
    self.ui.menu:registerToMainMenu(self)
end

function Backgammon:playerName()
    local name = Protocol.clean_name(self.settings:readSetting("name"))
    if name == "" then name = Protocol.clean_name(Device.model or "") end
    if name == "" then name = _("Player") end
    return name
end

function Backgammon:editName(touchmenu_instance)
    local dialog
    dialog = InputDialog:new{
        title = _("Your name"),
        input = self:playerName(),
        description = _("Shown to the other player and in the list of games."),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                self.settings:saveSetting("name", Protocol.clean_name(dialog:getInputText()))
                self.settings:flush()
                UIManager:close(dialog)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Backgammon:showRules()
    UIManager:show(InfoMessage:new{
        text = _([[Each player has 15 checkers and moves them around the board by the numbers rolled on two dice, towards their home board (points 1–6, bottom right). Doubles are played four times. Both dice must be used when possible; when only one can be used, it must be the larger one if it can be played.

A checker may land on a point with at most one opposing checker; that checker is hit and goes to the bar. Checkers on the bar must enter the opponent's home board before any other move.

Once all 15 checkers are in the home board, they are borne off. Whoever bears off all their checkers first wins.

Both devices must be on the same Wi-Fi network. One player hosts the game, the other finds it in Find a game or joins by the address shown on the host's screen.]]),
    })
end

function Backgammon:mainMenu()
    return {
        { text = _("Host a game"), backgammon_item = "host", callback = function() self:hostGame() end },
        { text = _("Find a game"), backgammon_item = "find", callback = function() self:findGames() end },
        { text = _("Join by address…"), backgammon_item = "join", callback = function() self:joinByAddress() end,
            separator = true },
        { text_func = function() return T(_("Your name: %1"), self:playerName()) end, backgammon_item = "name",
            keep_menu_open = true,
            callback = function(touchmenu_instance) self:editName(touchmenu_instance) end },
        { text = _("Rules"), backgammon_item = "rules", keep_menu_open = true,
            callback = function() self:showRules() end },
    }
end

function Backgammon:addToMainMenu(menu_items)
    menu_items.backgammon = {
        text = _("Backgammon"),
        sorting_hint = "tools",
        sub_item_table_func = function() return self:mainMenu() end,
    }
end

function Backgammon:onSuspend()
    -- Wi-Fi goes off while the device sleeps: leave instead of timing out.
    stop_finder()
    Backgammon.endGame()
end

function Backgammon:onExit()
    stop_finder()
    Backgammon.endGame()
end

return Backgammon
