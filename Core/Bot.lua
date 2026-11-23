local _, ns = ...

local Chess = ns.Chess
local PAWN = Chess.PAWN
local abs, max, min, floor, random = math.abs, math.max, math.min, math.floor, math.random

local MATE, INF = 100000, 1000000
local SLICE_MS = 8
local CHECK_EVERY = 256
local VALUES = { 100, 320, 330, 500, 900, 0 }
local CENTER_WEIGHT = { 2, 8, 5, 0, 1, 0 }

local Bot = {
    LEVELS = {
        { name = "Murloc", elo = 300, depth = 1, time = 400, margin = 250, blunder = 0.30 },
        { name = "Defias Thug", elo = 600, depth = 1, time = 600, margin = 120, blunder = 0.12 },
        { name = "Footman", elo = 900, depth = 2, time = 900, margin = 60, blunder = 0.05 },
        { name = "Knight-Captain", elo = 1200, depth = 2, time = 1500, margin = 25, blunder = 0.01 },
        { name = "Champion", elo = 1500, depth = 3, time = 2500, margin = 10, blunder = 0 },
        { name = "Archmage", elo = 1800, depth = 4, time = 4000, margin = 0, blunder = 0 },
    },
}
ns.Bot = Bot

local MIRROR, BONUS = {}, {}
for square = 1, 64 do
    MIRROR[square] = (7 - floor((square - 1) / 8)) * 8 + (square - 1) % 8 + 1
end
for kind = 1, 6 do
    BONUS[kind] = {}
    for square = 1, 64 do
        local file, rank = (square - 1) % 8, floor((square - 1) / 8)
        local centrality = min(file, 7 - file) + min(rank, 7 - rank)
        BONUS[kind][square] = CENTER_WEIGHT[kind] * centrality + (kind == PAWN and rank * 4 or 0)
    end
end

local job

local function evaluate(position)
    local board, score = position.board, 0
    for square = 1, 64 do
        local piece = board[square]
        if piece > 0 then
            score = score + VALUES[piece] + BONUS[piece][square]
        elseif piece < 0 then
            score = score - VALUES[-piece] - BONUS[-piece][MIRROR[square]]
        end
    end
    return score * position.turn
end

local function orderMoves(moves)
    for _, move in ipairs(moves) do
        local order = 0
        if move.capture ~= 0 then
            order = 1000 + 10 * VALUES[abs(move.capture)] - VALUES[abs(move.piece)]
        end
        move.order = order + (move.promo and VALUES[move.promo] or 0)
    end
    table.sort(moves, function(a, b)
        return a.order > b.order
    end)
end

local function checkpoint()
    job.nodes = job.nodes + 1
    if job.nodes % CHECK_EVERY ~= 0 then
        return
    end
    local now = debugprofilestop()
    if now - job.started > job.level.time then
        job.expired = true
    elseif now - job.sliceStart > SLICE_MS then
        coroutine.yield()
    end
end

local function quiesce(position, alpha, beta)
    checkpoint()
    local stand = evaluate(position)
    if stand >= beta then
        return beta
    end
    alpha = max(alpha, stand)

    local moves = position:LegalMoves(true)
    orderMoves(moves)
    for _, move in ipairs(moves) do
        local undo = position:Make(move)
        local score = -quiesce(position, -beta, -alpha)
        position:Unmake(move, undo)
        if job.expired then
            return 0
        elseif score >= beta then
            return beta
        end
        alpha = max(alpha, score)
    end
    return alpha
end

local function search(position, depth, alpha, beta, ply)
    if depth <= 0 then
        return quiesce(position, alpha, beta)
    end
    checkpoint()

    local moves = position:LegalMoves()
    if #moves == 0 then
        return position:InCheck() and (ply - MATE) or 0
    end
    orderMoves(moves)
    for _, move in ipairs(moves) do
        local undo = position:Make(move)
        local score = -search(position, depth - 1, -beta, -alpha, ply + 1)
        position:Unmake(move, undo)
        if job.expired then
            return 0
        elseif score >= beta then
            return beta
        end
        alpha = max(alpha, score)
    end
    return alpha
end

local function searchRoot(position, moves, depth, margin)
    local results, best = {}, -INF
    for _, move in ipairs(moves) do
        local lower = best == -INF and -INF or best - margin - 1
        local undo = position:Make(move)
        local score = -search(position, depth - 1, -INF, -lower, 1)
        position:Unmake(move, undo)
        if job.expired then
            return nil
        elseif score > lower then
            results[#results + 1] = { move = move, score = score }
            best = max(best, score)
        end
    end
    table.sort(results, function(a, b)
        return a.score > b.score
    end)
    return results
end

local function bestFirst(moves, results)
    local ordered, kept = {}, {}
    for _, result in ipairs(results) do
        ordered[#ordered + 1] = result.move
        kept[result.move] = true
    end
    for _, move in ipairs(moves) do
        if not kept[move] then
            ordered[#ordered + 1] = move
        end
    end
    return ordered
end

local function chooseMove(moves, results, level)
    if not results or random() < level.blunder then
        return moves[random(#moves)]
    end
    local candidates = {}
    for _, result in ipairs(results) do
        if result.score >= results[1].score - level.margin then
            candidates[#candidates + 1] = result.move
        end
    end
    return candidates[random(#candidates)]
end

local function run()
    local position, level = job.position, job.level
    local moves = position:LegalMoves()
    local results
    for depth = 1, level.depth do
        local found = searchRoot(position, moves, depth, level.margin)
        if not found then
            break
        end
        results, moves = found, bestFirst(moves, found)
    end
    job.move = chooseMove(moves, results, level)
end

local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(self)
    local current = job
    current.sliceStart = debugprofilestop()
    local ok, err = coroutine.resume(current.thread)
    if not ok then
        job = nil
        self:Hide()
        error(err)
    elseif coroutine.status(current.thread) == "dead" then
        job = nil
        self:Hide()
        current.callback(current.move)
    end
end)

function Bot.Think(position, level, callback)
    job = {
        position = Chess.Position.New(position:GetFEN()),
        level = level,
        callback = callback,
        thread = coroutine.create(run),
        nodes = 0,
        started = debugprofilestop(),
        expired = false,
    }
    ticker:Show()
end

function Bot.Cancel()
    job = nil
    ticker:Hide()
end
