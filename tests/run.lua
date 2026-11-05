-- Off-device tests. Run from the repo root:  luajit tests/run.lua
package.path = "./?.lua;" .. package.path

local Rules = require("backgammon/rules")
local Protocol = require("backgammon/protocol")
local Match = require("backgammon/match")
local Net = require("backgammon/net")

local passed, failed = 0, 0
local function eq(actual, expected, name)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        print(("FAIL %s\n  expected: %q\n  actual:   %q"):format(name, tostring(expected), tostring(actual)))
    end
end

-- Seeded random numbers, the same on every Lua version.
local function rng(seed)
    local s = seed
    return function(n)
        s = (s * 1103515245 + 12345) % 2147483648
        return math.floor(s / 65536) % n + 1
    end
end

-- Rules -----------------------------------------------------------------------
local s = Rules.new()
eq(Rules.pips(s, "white") .. " " .. Rules.pips(s, "black"), "167 167", "starting pips")
eq(Rules.count(s, "white", 24) .. Rules.count(s, "black", 24) .. s.points[1], "22-2", "both sides see their own 24")
eq(Rules.opponent(s, "white", 19), 5, "black's 6 is white's 19")
eq(Rules.target(s, "white", 24, 5), nil, "blocked point")
eq(Rules.target(s, "white", 24, 6), 18, "open point")
eq(Rules.target(s, "white", 23, 1), nil, "no checker there")
eq(Rules.target(s, "white", 6, 6), nil, "no bearing off before all are home")

-- an empty board with a few checkers
local function empty(off_white, off_black)
    local e = Rules.new()
    for i = 1, 24 do e.points[i] = 0 end
    e.off.white, e.off.black = off_white or 0, off_black or 0
    return e
end
s = empty()
s.points[10] = 1
s.points[7] = -1
s.bar.white = 1
eq(Rules.target(s, "white", 10, 3), nil, "checkers on the bar enter first")
eq(Rules.target(s, "white", Rules.BAR, 3), 22, "entering")
local to, hit = Rules.move(s, "white", Rules.BAR, 3)
eq(to .. tostring(hit) .. s.bar.white, "22false0", "entered")
to, hit = Rules.move(s, "white", 10, 3)
eq(to .. tostring(hit) .. s.bar.black .. s.points[7], "7true11", "hit goes to the bar")
eq(Rules.count(s, "black", Rules.BAR), 1, "black on the bar")
eq(Rules.target(s, "black", 7, 1), nil, "black must enter first")
eq(Rules.target(s, "black", Rules.BAR, 3), 22, "black enters on its 22 (point 3)")

s = empty(12, 15)
s.points[5], s.points[3] = 2, 1
eq(Rules.all_home(s, "white"), true, "all home")
eq(Rules.target(s, "white", 3, 3), 0, "bear off with the exact die")
eq(Rules.target(s, "white", 5, 6), 0, "a higher die bears off from the highest point")
eq(Rules.target(s, "white", 3, 6), nil, "but not from a lower one")
eq(Rules.target(s, "white", 5, 2), 3, "moving inside the home board")
Rules.move(s, "white", 3, 3)
eq(s.off.white, 13, "borne off")
s.points[5] = 0
s.points[9] = 2
eq(Rules.target(s, "white", 5, 5), nil, "no bearing off with a checker outside")

-- turns
s = empty(14, 13)
s.points[10] = 1
s.points[1] = -2
local t = Rules.turn(s, "white", 3, 6)
eq(t.max .. " " .. #t:moves() .. " " .. t:moves()[1].die, "1 1 6", "only one die can be used: the larger one")
eq(t:play(10, 3), nil, "the smaller one is refused")
eq(t:play(10, 6), 4, "the larger one is played")
eq(t:done(), true, "turn done after one die")

s = empty(14, 13)
s.points[10] = 1
s.points[4] = -2
t = Rules.turn(s, "white", 6, 3)
local ms = t:moves()
eq(t.max .. " " .. #ms .. " " .. ms[1].from .. "/" .. ms[1].die, "2 1 10/3", "both dice must be used when they can")

s = empty(14, 13)
s.points[20] = 1
s.points[14], s.points[15] = -2, -2
t = Rules.turn(s, "white", 6, 5)
eq(t.max .. tostring(t:done()) .. #t:moves(), "0true0", "no move possible")
eq(#t:encode(), 0, "empty move")

t = Rules.turn(Rules.new(), "white", 6, 6)
eq(#t.dice .. " " .. t.max, "4 4", "doubles: four moves")
eq(t:play(24, 6), 18, "move 1")
eq(t:play(24, 6), 18, "move 2")
eq(t:play(13, 6), 7, "move 3")
eq(t:done(), false, "one move left")
eq(t:undo() and #t.played .. #t.dice, "22", "undo takes back the last move")
eq(Rules.count(t.state, "white", 13), 5, "undone checker is back")
eq(Rules.count(t.start, "white", 18), 0, "the start position stays")
t:play(13, 6); t:play(13, 6)
eq(t:done() and table.concat(t:encode(), " "), "24/6 24/6 13/6 13/6", "encoded moves")
eq(Rules.decode_move("25/3"), 25, "decode bar")
eq(Rules.decode_move("26/3") or Rules.decode_move("3/7") or Rules.decode_move("x"), nil, "bad moves rejected")

-- Protocol ----------------------------------------------------------------------
eq(Protocol.clean_name("  Ann\nB\tc  "), "Ann B c", "names lose control characters")
eq(Protocol.clean_name(string.rep("ž", 30)), string.rep("ž", 24), "names are cut by characters")
local cmd, words, rest = Protocol.parse("HELLO 1 Žluťoučký kůň")
eq(cmd .. "|" .. words[1] .. "|" .. rest, "HELLO|1|1 Žluťoučký kůň", "parse")
eq(Protocol.parse("hello"), nil, "commands are upper case")
local buf = Protocol.buffer()
eq(#buf:push("PI"), 0, "partial line waits")
local lines = buf:push("NG\r\nSHOT 1 2\nRES")
eq(table.concat(lines, ","), "PING,SHOT 1 2", "complete lines")
eq(buf:push("ULT\n")[1], "RESULT", "rest of the line")
eq(select(2, buf:push(string.rep("x", 600))), "too long", "endless line is an error")
local h, p = Protocol.parse_address(" 192.168.1.5 ")
eq(h .. ":" .. p, "192.168.1.5:" .. Protocol.PORT, "address without port")
h, p = Protocol.parse_address("10.0.0.2:7000")
eq(h .. ":" .. p, "10.0.0.2:7000", "address with port")
eq(Protocol.parse_address("10.0.0.2:99999"), nil, "port out of range")
eq(Protocol.parse_address("a b"), nil, "invalid address")
eq(table.concat(Protocol.broadcasts("192.168.1.5"), ","), "255.255.255.255,192.168.1.255", "broadcast addresses")
eq(#Protocol.broadcasts(nil), 1, "global broadcast without an address")
eq(Protocol.is_discover(Protocol.discover()), true, "discover")
eq(Protocol.is_discover("DISCOVER 99"), false, "other version ignored")
local ann = Protocol.parse_announce(Protocol.announce(7541, "Kindle Paperwhite"))
eq(ann.port .. " " .. ann.name, "7541 Kindle Paperwhite", "announce round trip")
eq(Protocol.parse_announce("GAME 99 7541 x"), nil, "announce of another version ignored")

-- Match: two players wired together ------------------------------------------
local function pair(seed)
    local host, guest
    local to_guest, to_host = {}, {}
    host = Match.new{ role = "host", name = "Host", rand = rng(seed), send = function(l) table.insert(to_guest, l) end }
    guest = Match.new{ role = "guest", name = "Guest", rand = rng(seed + 100), send = function(l) table.insert(to_host, l) end }
    local events = { host = {}, guest = {} }
    local function deliver()
        local any = true
        while any do
            any = false
            while #to_host > 0 do
                any = true
                local l = table.remove(to_host, 1):gsub("\n$", "")
                local ev, err = host:receive(l)
                assert(not err, "host: " .. tostring(err) .. " on " .. l)
                if ev then table.insert(events.host, ev.type) end
            end
            while #to_guest > 0 do
                any = true
                local l = table.remove(to_guest, 1):gsub("\n$", "")
                local ev, err = guest:receive(l)
                assert(not err, "guest: " .. tostring(err) .. " on " .. l)
                if ev then table.insert(events.guest, ev.type) end
            end
        end
    end
    return host, guest, deliver, events
end

-- plays random legal moves until the game ends
local function play(a, z, deliver_fn, pick)
    for _step = 1, 2000 do
        if a.phase ~= "playing" then break end
        local p = a:my_turn() and a or z
        while not p.current:done() do
            local ms = p.current:moves()
            local m = ms[pick(#ms)]
            p:play(m.from, m.die)
        end
        p:finish_turn()
        deliver_fn()
    end
end

local host, guest, deliver, events = pair(7)
eq(host.phase .. host.color .. guest.color, "waitingwhiteblack", "host plays white")
eq(host:start(), nil, "no start without an opponent")
guest:hello()
deliver()
eq(host.peer .. "/" .. guest.peer, "Guest/Host", "names exchanged")
eq(host.phase .. guest.phase, "playingplaying", "the game starts when the guest joins")
eq(events.guest[#events.guest], "start", "guest: start event")
eq((host.turn == "me") ~= (guest.turn == "me"), true, "exactly one player's turn")
local first = host:my_turn() and host or guest
eq(first.dice[1] > first.dice[2], true, "the opening dice: higher first")
eq((first == host and guest or host).dice[1], first.dice[1], "both know the opening dice")
eq(first:finish_turn(), nil, "the dice must be played first")
local pick = rng(11)
play(host, guest, deliver, pick)
eq(host.phase .. guest.phase, "overover", "the game ends")
eq((host.winner == "me") ~= (guest.winner == "me"), true, "exactly one winner")
local winner = host.winner == "me" and host or guest
eq(Rules.won(host.position, winner.color) and Rules.won(guest.position, winner.color), true, "both positions agree")
eq(winner.score.me .. (winner == host and guest or host).score.peer, "11", "score counted on both sides")

guest:request_rematch()
deliver()
eq(host.phase, "over", "rematch needs both players")
eq(events.host[#events.host], "rematch_request", "host: rematch request")
host:request_rematch()
deliver()
eq(host.phase .. guest.phase, "playingplaying", "rematch: a new game starts")
eq(Rules.pips(host.position, "white"), 167, "rematch: starting position")
eq(host.score.me + host.score.peer, 1, "rematch keeps the score")
-- the other order
play(host, guest, deliver, pick)
host:request_rematch()
deliver()
guest:request_rematch()
deliver()
eq(host.phase .. guest.phase, "playingplaying", "rematch asked by the host first")
eq(host.score.me + host.score.peer, 2, "two games played")

-- many random games stay in sync
for seed = 20, 40 do
    local h, g, d = pair(seed)
    g:hello()
    d()
    play(h, g, d, rng(seed * 3))
    eq(h.phase .. g.phase, "overover", "random game " .. seed)
end

-- protocol errors
host, guest, deliver = pair(3)
eq(select(2, guest:receive("MOVE 24/3")), "unexpected MOVE", "move before the game")
eq(select(2, guest:receive("HELLO 1 x")), "unexpected HELLO", "guest doesn't take HELLO")
eq(select(2, host:receive("HELLO 99 x")), "version", "other version refused")
eq(host:receive("FUTURE stuff"), nil, "unknown commands are ignored")
eq(select(2, host:receive("ERROR busy")), "busy", "ERROR ends the match")
guest:receive("WELCOME 1 H")
eq(select(2, guest:receive("START 3 3")), "bad START", "opening dice must differ")
guest:receive("START 6 2")
eq(guest.turn .. guest.dice[1] .. guest.dice[2], "peer62", "host starts with 6-2")
eq(select(2, guest:receive("ROLL 1 2")), "unexpected ROLL", "no roll on the opening turn")
eq(select(2, guest:receive("MOVE 24/6")), "bad MOVE", "not all dice played")
eq(select(2, guest:receive("MOVE 24/5 24/2")), "bad MOVE", "move onto a blocked point")
eq(select(2, guest:receive("MOVE 24/6 24/6")), "bad MOVE", "die not rolled")
local ev = guest:receive("MOVE 13/6 8/2")
eq(ev.type .. #ev.moves .. guest.turn, "moved2me", "valid move: guest's turn")
eq(guest.dice ~= nil and guest.current ~= nil, true, "guest rolled")
eq(Rules.count(guest.position, "white", 7), 1, "the host's checker moved")

-- the host's opponent leaves before the game
host = Match.new{ role = "host", name = "H", send = function() end }
host:receive("HELLO 1 G")
host:drop_peer()
eq(host.peer == nil and host.phase == "waiting", true, "drop_peer waits for another opponent")

-- Net with fake sockets ----------------------------------------------------------
local function fake_tcp(incoming)
    local s = { sent = "", incoming = incoming or {}, closed = false }
    function s:settimeout() end
    function s:setoption() return true end
    function s:send(data) self.sent = self.sent .. data; return #data end
    function s:receive()
        local chunk = table.remove(self.incoming, 1)
        if chunk == "CLOSE" then return nil, "closed", "" end
        if chunk then return nil, "timeout", chunk end
        return nil, "timeout", ""
    end
    function s:close() self.closed = true end
    return s
end

local sock = fake_tcp({ "PING\nSHO", "T 1 2\n" })
local conn = Net.connection(sock, 0)
local got = conn:poll(5)
eq(table.concat(got, ","), "PING", "first poll: one line")
eq(conn.last_seen, 5, "data updates last_seen")
eq(conn:poll(6)[1], "SHOT 1 2", "line completed in the next poll")
eq(#conn:poll(7), 0, "nothing more")
eq(conn.last_seen, 6, "no data, last_seen kept")
conn:send("BYE\n")
eq(sock.sent, "BYE\n", "send")
sock.incoming = { "CLOSE" }
eq(select(2, conn:poll(8)), "closed", "closed connection reported")
eq(sock.closed, true, "socket closed")

-- partial sends are kept for later
sock = fake_tcp()
local accept = 2
function sock:send(data)
    local n = math.min(accept, #data)
    self.sent = self.sent .. data:sub(1, n)
    if n < #data then return nil, "timeout", n end
    return n
end
conn = Net.connection(sock, 0)
conn:send("ABCDEF\n")
eq(sock.sent, "AB", "partial send")
accept = 100
conn:poll(1)
eq(sock.sent, "ABCDEF\n", "rest sent on the next poll")

-- discovery
local function fake_udp()
    local u = { out = {}, inbox = {} }
    function u:setsockname(_h, port) self.port = port; return true end
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
local udps = {}
local fake_socket = {
    udp = function() local u = fake_udp(); table.insert(udps, u); return u end,
    bind = function() local s = fake_tcp(); s.accept = function() return nil end; return s end,
}
local hst = Net.host(fake_socket, 7541)
local hudp = udps[#udps]
eq(hudp.port, Protocol.DISCOVERY_PORT, "host listens for discovery")
hudp.inbox = { { "DISCOVER 1", "10.0.0.9", 7543 }, { "junk", "10.0.0.8", 1 } }
hst:answer("Host")
eq(#hudp.out .. " " .. hudp.out[1][1] .. " " .. hudp.out[1][2], "1 GAME 1 7541 Host 10.0.0.9", "host answers DISCOVER only")
hudp.inbox = { { "DISCOVER 1", "10.0.0.9", 7543 } }
hst:answer(nil)
eq(#hudp.out, 1, "no answers once the game is full")

local search = Net.search(fake_socket, "10.0.0.5")
local sudp = udps[#udps]
eq(sudp.port, Protocol.SEARCH_PORT, "search listens on its port")
search:send()
eq(#sudp.out .. " " .. sudp.out[2][2], "2 10.0.0.255", "discover broadcast to both addresses")
sudp.inbox = { { "GAME 1 7541 Host", "10.0.0.9", 7542 }, { "GAME 1 7541 Host", "10.0.0.9", 7542 } }
eq(search:poll(1), true, "found a game")
eq(#search.games .. " " .. search.games[1].name .. " " .. search.games[1].ip, "1 Host 10.0.0.9", "one entry per host")
eq(search:poll(2), false, "nothing new")
eq(search:expire(4, 5), false, "recently seen game stays")
eq(search:expire(7, 5), true, "silent game dropped")
eq(#search.games, 0, "list empty")

-- L10n: every _("…") of main.lua is translated, and the catalog has no stale entries
loadstring = loadstring or load
local function msgids(path)
    local src = io.open(path):read("*a")
    local ids = {}
    for lit in src:gmatch('_%(%s*(".-[^\\]")%s*%)') do ids[loadstring("return " .. lit)()] = true end
    for lit in src:gmatch('_%(%s*%[%[(.-)%]%]%s*%)') do ids[lit] = true end
    return ids
end
local used = msgids("main.lua")
local cs = require("backgammon/l10n/cs")
local missing, stale = {}, {}
for id in pairs(used) do if not cs[id] then missing[#missing + 1] = id end end
for id in pairs(cs) do if not used[id] then stale[#stale + 1] = id end end
table.sort(missing); table.sort(stale)
eq(table.concat(missing, " | "), "", "all strings translated to Czech")
eq(table.concat(stale, " | "), "", "no unused Czech translations")

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
