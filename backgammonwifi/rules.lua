--[[--
Backgammon rules. Pure Lua: no KOReader modules.

Position: points[1..24] hold checkers, > 0 white, < 0 black; bar and off count
each colour's checkers on the bar and borne off. White moves from point 24 to
point 1, black from 1 to 24.

Most functions take points from one colour's side ("rel"): 24..1 in the order
that colour moves, 25 = its bar, 0 = borne off. rel 1..6 is its home board.
For white rel = the point, for black rel = 25 - the point.

A turn: the dice (four moves on doubles) must be used as fully as possible;
when only one die of two different ones can be used, it must be the larger one
if that can be played. Turn objects enforce this step by step.
]]

local M = {}

M.CHECKERS = 15
M.BAR = 25
M.OFF = 0

local SIGN = { white = 1, black = -1 }
local OTHER = { white = "black", black = "white" }

function M.other(color)
    return OTHER[color]
end

--- Point number of `rel` from `color`'s side (rel 1..24).
function M.abs(color, rel)
    return color == "white" and rel or 25 - rel
end

--- Starting position: from each side 2 on 24, 5 on 13, 3 on 8 and 5 on 6.
function M.new()
    local s = { points = {}, bar = { white = 0, black = 0 }, off = { white = 0, black = 0 } }
    for i = 1, 24 do s.points[i] = 0 end
    for _i, color in ipairs({ "white", "black" }) do
        for rel, n in pairs({ [24] = 2, [13] = 5, [8] = 3, [6] = 5 }) do
            s.points[M.abs(color, rel)] = n * SIGN[color]
        end
    end
    return s
end

function M.copy(s)
    local c = { points = {}, bar = { white = s.bar.white, black = s.bar.black },
        off = { white = s.off.white, black = s.off.black } }
    for i = 1, 24 do c.points[i] = s.points[i] end
    return c
end

--- `color`'s checkers on rel (1..24 or the bar).
function M.count(s, color, rel)
    if rel == M.BAR then return s.bar[color] end
    local v = s.points[M.abs(color, rel)] * SIGN[color]
    return v > 0 and v or 0
end

--- The opponent's checkers on `color`'s rel 1..24.
function M.opponent(s, color, rel)
    return M.count(s, OTHER[color], 25 - rel)
end

--- All of `color`'s checkers are in its home board (or borne off).
function M.all_home(s, color)
    if s.bar[color] > 0 then return false end
    for rel = 7, 24 do
        if M.count(s, color, rel) > 0 then return false end
    end
    return true
end

--- Where a checker of `color` on rel `from` goes with `die`: rel 1..24, or 0
-- when borne off; nil when it can't move.
function M.target(s, color, from, die)
    if s.bar[color] > 0 and from ~= M.BAR then return nil end
    if M.count(s, color, from) == 0 then return nil end
    local to = from - die
    if to >= 1 then
        if M.opponent(s, color, to) >= 2 then return nil end
        return to
    end
    if not M.all_home(s, color) then return nil end
    if to < 0 then
        -- a higher die bears off only from the highest occupied point
        for rel = from + 1, 6 do
            if M.count(s, color, rel) > 0 then return nil end
        end
    end
    return 0
end

--- Moves a checker (target() must allow it). Returns to, hit (true when an
-- opponent's checker went to the bar).
function M.move(s, color, from, die)
    local to = math.max(from - die, 0)
    local sign = SIGN[color]
    if from == M.BAR then s.bar[color] = s.bar[color] - 1
    else
        local i = M.abs(color, from)
        s.points[i] = s.points[i] - sign
    end
    if to == 0 then
        s.off[color] = s.off[color] + 1
        return to, false
    end
    local i = M.abs(color, to)
    local hit = s.points[i] == -sign
    if hit then
        s.points[i] = 0
        s.bar[OTHER[color]] = s.bar[OTHER[color]] + 1
    end
    s.points[i] = s.points[i] + sign
    return to, hit
end

function M.won(s, color)
    return s.off[color] == M.CHECKERS
end

--- How `winner` won: 1 a single game, 2 a gammon (the loser bore off no
-- checker), 3 a backgammon (and still has one on the bar or in the winner's
-- home board).
function M.result(s, winner)
    local loser = OTHER[winner]
    if s.off[loser] > 0 then return 1 end
    if s.bar[loser] > 0 then return 3 end
    for rel = 19, 24 do
        if M.count(s, loser, rel) > 0 then return 3 end
    end
    return 2
end

--- Pips `color` still has to move.
function M.pips(s, color)
    local n = 25 * s.bar[color]
    for rel = 1, 24 do n = n + rel * M.count(s, color, rel) end
    return n
end

--- Dice to play for a roll: two, or four on doubles.
function M.dice(d1, d2)
    if d1 == d2 then return { d1, d1, d1, d1 } end
    return { d1, d2 }
end

local function without(dice, die)
    local out, removed = {}, false
    for _i, d in ipairs(dice) do
        if d == die and not removed then removed = true else out[#out + 1] = d end
    end
    return out
end

local function distinct(dice)
    local out, seen = {}, {}
    for _i, d in ipairs(dice) do
        if not seen[d] then seen[d] = true; out[#out + 1] = d end
    end
    return out
end

--- The most dice of `dice` that can be played from position `s`.
local function playable(s, color, dice)
    if #dice == 0 then return 0 end
    local best = 0
    for _i, die in ipairs(distinct(dice)) do
        local rest = without(dice, die)
        for from = M.BAR, 1, -1 do
            if M.target(s, color, from, die) then
                local after = M.copy(s)
                M.move(after, color, from, die)
                local n = 1 + playable(after, color, rest)
                if n == #dice then return n end
                if n > best then best = n end
            end
        end
    end
    return best
end
M.playable = playable

-- A turn ------------------------------------------------------------------------

local Turn = {}
Turn.__index = Turn

--- The turn of `color` with dice d1, d2 from position `s` (not changed; the
-- turn works on a copy, see turn.state).
function M.turn(s, color, d1, d2)
    local dice = M.dice(d1, d2)
    local t = setmetatable({
        start = M.copy(s), state = M.copy(s), color = color, roll = { d1, d2 },
        all = dice, dice = dice, played = {},
    }, Turn)
    t.max = playable(t.state, color, dice)
    if t.max == 1 and d1 ~= d2 then
        -- only one die can be used: the larger one when it can be
        local big = math.max(d1, d2)
        for from = M.BAR, 1, -1 do
            if M.target(t.state, color, from, big) then t.only = big; break end
        end
    end
    return t
end

--- Legal moves now: list of { from, die, to }.
function Turn:moves()
    local out = {}
    local need = self.max - #self.played
    if need <= 0 then return out end
    for _i, die in ipairs(distinct(self.dice)) do
        if not self.only or die == self.only then
            local rest = without(self.dice, die)
            for from = M.BAR, 1, -1 do
                local to = M.target(self.state, self.color, from, die)
                if to then
                    local after = M.copy(self.state)
                    M.move(after, self.color, from, die)
                    if 1 + playable(after, self.color, rest) == need then
                        out[#out + 1] = { from = from, die = die, to = to }
                    end
                end
            end
        end
    end
    return out
end

function Turn:legal(from, die)
    for _i, m in ipairs(self:moves()) do
        if m.from == from and m.die == die then return m end
    end
end

--- Plays a move. Returns to, hit; nil when it isn't legal.
function Turn:play(from, die)
    if not self:legal(from, die) then return nil end
    local to, hit = M.move(self.state, self.color, from, die)
    self.dice = without(self.dice, die)
    table.insert(self.played, { from = from, die = die, to = to, hit = hit })
    return to, hit
end

--- Takes back the last move.
function Turn:undo()
    if #self.played == 0 then return false end
    table.remove(self.played)
    local played = self.played
    self.state, self.dice, self.played = M.copy(self.start), self.all, {}
    for _i, m in ipairs(played) do self:play(m.from, m.die) end
    return true
end

--- All the dice that can be played have been.
function Turn:done()
    return #self.played >= self.max
end

--- Wire form of the moves played: "24/6 13/5".
function Turn:encode()
    local out = {}
    for _i, m in ipairs(self.played) do out[#out + 1] = m.from .. "/" .. m.die end
    return out
end

--- "24/6" → from, die; nil when malformed.
function M.decode_move(word)
    local from, die = (word or ""):match("^(%d+)/(%d)$")
    from, die = tonumber(from), tonumber(die)
    if not from or from < 1 or from > M.BAR or die < 1 or die > 6 then return nil end
    return from, die
end

return M
