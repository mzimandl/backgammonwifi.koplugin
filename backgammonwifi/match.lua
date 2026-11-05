--[[--
One match between two players: the state machine on top of the wire format.
Pure Lua: no KOReader modules, no sockets. main.lua passes in `send(line)`
and feeds received lines to receive().

The host plays white, the guest black. Phases: "waiting" (no opponent yet),
"opening" (the opening roll), "playing", "over". In the opening roll each
player rolls one die (roll_opening(), OPEN); both sides compare them the same
way: the higher die starts and plays both, equal dice are rolled again. After
that each device rolls its own dice when its player rolls them (roll(), ROLL)
and sends its moves (MOVE); the other side checks them against the rules.

receive() and the local actions return an event table for the UI (or nil when
nothing visible changed); on a protocol error receive() returns nil, error.
Events: joined, opening (one opening die known: mine or the opponent's),
opening_tie (equal: roll again), start, rolled (the opponent's dice), moved (the opponent's
moves; my turn begins, waiting for roll()), roll (my dice), played (my turn
ended), rematch_request, rematch, left.
]]

local Protocol = require("backgammonwifi/protocol")
local Rules = require("backgammonwifi/rules")

local M = {}

local Match = {}
Match.__index = Match

--- opts: role = "host" | "guest", name, send(line), rand (math.random)
function M.new(opts)
    local m = setmetatable({
        role = opts.role,
        color = opts.role == "host" and "white" or "black",
        name = Protocol.clean_name(opts.name),
        send_line = opts.send,
        rand = opts.rand or math.random,
        score = { me = 0, peer = 0 },
    }, Match)
    m.peer_color = Rules.other(m.color)
    m:reset()
    return m
end

function Match:reset()
    self.phase = self.peer and "opening" or "waiting"
    self.my_open, self.peer_open = nil, nil
    self.position = Rules.new()
    self.turn, self.dice, self.current, self.winner = nil, nil, nil, nil
    self.rematch, self.peer_rematch = false, false
    self.last_peer_moves = nil
end

function Match:send(...)
    if self.send_line then self.send_line(Protocol.line(...)) end
end

--- Guest: introduce ourselves after connecting.
function Match:hello()
    self:send("HELLO", Protocol.VERSION, self.name)
end

function Match:ping()
    self:send("PING")
end

function Match:bye()
    self:send("BYE")
end

--- Host: the opponent left before the game started; wait for another one.
function Match:drop_peer()
    self.peer = nil
    self:reset()
    self.score = { me = 0, peer = 0 }
end

local function die(word)
    local d = tonumber(word)
    if not d or d % 1 ~= 0 or d < 1 or d > 6 then return nil end
    return d
end

-- My turn begins with dice d1, d2.
function Match:my_turn_begins(d1, d2)
    self.turn = "me"
    self.dice = { d1, d2 }
    self.current = Rules.turn(self.position, self.color, d1, d2)
end

function Match:begin(host_die, guest_die)
    self.phase = "playing"
    local first = host_die > guest_die and "host" or "guest"
    local d1, d2 = math.max(host_die, guest_die), math.min(host_die, guest_die)
    if first == self.role then self:my_turn_begins(d1, d2)
    else
        self.turn, self.dice = "peer", { d1, d2 }
    end
    return { type = "start", turn = self.turn, host_die = host_die, guest_die = guest_die }
end

--- Both opening dice known: start, or roll again when they are equal.
function Match:resolve_opening(ev)
    local mine, theirs = self.my_open, self.peer_open
    if not (mine and theirs) then return ev end
    self.my_open, self.peer_open = nil, nil
    if mine == theirs then return { type = "opening_tie", die = mine } end
    if self.role == "host" then return self:begin(mine, theirs) end
    return self:begin(theirs, mine)
end

--- The opening roll is waiting for my die.
function Match:needs_opening_roll()
    return self.phase == "opening" and self.my_open == nil
end

--- Rolls my opening die. Returns the "opening" event, or "opening_tie" /
-- "start" when the opponent's die is already known.
function Match:roll_opening()
    if not self:needs_opening_roll() then return nil end
    self.my_open = self.rand(6)
    self:send("OPEN", self.my_open)
    return self:resolve_opening({ type = "opening", mine = true, die = self.my_open })
end

function Match:my_turn()
    return self.phase == "playing" and self.turn == "me" and self.current ~= nil
end

--- My turn has begun and the dice are still to be rolled.
function Match:needs_roll()
    return self.phase == "playing" and self.turn == "me" and self.current == nil
end

--- Rolls my dice. Returns the "roll" event.
function Match:roll()
    if not self:needs_roll() then return nil end
    local d1, d2 = self.rand(6), self.rand(6)
    self:send("ROLL", d1, d2)
    self:my_turn_begins(d1, d2)
    return { type = "roll", dice = self.dice }
end

--- Plays one of my moves. Returns to, hit, or nil when not legal.
function Match:play(from, die_value)
    if not self:my_turn() then return nil end
    return self.current:play(from, die_value)
end

function Match:undo()
    return self:my_turn() and self.current:undo()
end

--- Ends my turn when all playable dice are used. Returns the "played" event.
function Match:finish_turn()
    if not self:my_turn() or not self.current:done() then return nil end
    local t = self.current
    self:send("MOVE", unpack(t:encode()))
    self.position = t.state
    self.current, self.dice = nil, nil
    local ev = { type = "played", moves = t.played }
    if Rules.won(self.position, self.color) then
        self.phase, self.winner = "over", "me"
        self.score.me = self.score.me + 1
        ev.won = true
    else
        self.turn = "peer"
    end
    return ev
end

function Match:request_rematch()
    if self.phase ~= "over" or self.rematch then return nil end
    self.rematch = true
    self:send("REMATCH")
    if self.peer_rematch then
        self:reset()
        return { type = "rematch" }
    end
end

local handlers = {}

function handlers:HELLO(words, rest)
    if self.role ~= "host" then return nil, "unexpected HELLO" end
    if self.peer then return nil, "already joined" end
    if tonumber(words[1]) ~= Protocol.VERSION then
        self:send("ERROR", "version")
        return nil, "version"
    end
    self.peer = Protocol.clean_name(rest:match("^%S+%s*(.*)$"))
    self:send("WELCOME", Protocol.VERSION, self.name)
    self.phase = "opening"
    return { type = "joined", name = self.peer }
end

function handlers:WELCOME(words, rest)
    if self.role ~= "guest" or self.peer then return nil, "unexpected WELCOME" end
    if tonumber(words[1]) ~= Protocol.VERSION then return nil, "version" end
    self.peer = Protocol.clean_name(rest:match("^%S+%s*(.*)$"))
    self.phase = "opening"
    return { type = "joined", name = self.peer }
end

function handlers:ERROR(words)
    return nil, words[1] or "error"
end

function handlers:OPEN(words)
    if self.phase ~= "opening" or self.peer_open then return nil, "unexpected OPEN" end
    local d = die(words[1])
    if not d then return nil, "bad OPEN" end
    self.peer_open = d
    return self:resolve_opening({ type = "opening", mine = false, die = d })
end

function handlers:ROLL(words)
    if self.phase ~= "playing" or self.turn ~= "peer" or self.dice then return nil, "unexpected ROLL" end
    local d1, d2 = die(words[1]), die(words[2])
    if not d1 or not d2 then return nil, "bad ROLL" end
    self.dice = { d1, d2 }
    return { type = "rolled", dice = self.dice }
end

function handlers:MOVE(words)
    if self.phase ~= "playing" or self.turn ~= "peer" or not self.dice then return nil, "unexpected MOVE" end
    local t = Rules.turn(self.position, self.peer_color, self.dice[1], self.dice[2])
    for _i, w in ipairs(words) do
        local from, d = Rules.decode_move(w)
        if not from or not t:play(from, d) then return nil, "bad MOVE" end
    end
    if not t:done() then return nil, "bad MOVE" end
    self.position = t.state
    self.last_peer_moves = t.played
    local ev = { type = "moved", moves = t.played }
    if Rules.won(self.position, self.peer_color) then
        self.phase, self.winner, self.dice = "over", "peer", nil
        self.score.peer = self.score.peer + 1
        ev.won = true
        return ev
    end
    self.turn, self.dice = "me", nil
    return ev
end

function handlers:REMATCH()
    if self.phase ~= "over" then return nil end
    self.peer_rematch = true
    if self.rematch then
        self:reset()
        return { type = "rematch" }
    end
    return { type = "rematch_request" }
end

function handlers:BYE()
    return { type = "left" }
end

function handlers:PING()
    return nil
end

--- A line from the opponent.
function Match:receive(line)
    local cmd, words, rest = Protocol.parse(line)
    local handler = cmd and handlers[cmd]
    if not handler then return nil end -- unknown commands are ignored (newer versions)
    return handler(self, words, rest)
end

--- The position to show: with my moves so far while it's my turn.
function Match:shown()
    return self.current and self.current.state or self.position
end

return M
