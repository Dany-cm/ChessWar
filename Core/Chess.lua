local _, ns = ...

local PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING = 1, 2, 3, 4, 5, 6
local WHITE, BLACK = 1, -1
local PIECE_LETTERS = "PNBRQK"
local FILE_LETTERS = "abcdefgh"
local PROMOTIONS = { QUEEN, ROOK, BISHOP, KNIGHT }
local CORNER_RIGHT = { [1] = "Q", [8] = "K", [57] = "q", [64] = "k" }
local CASTLES = {
    { right = "K", kingTo = 7, rookFrom = 8, rookTo = 6 },
    { right = "Q", kingTo = 3, rookFrom = 1, rookTo = 4 },
}

local abs, floor = math.abs, math.floor

local Chess = {
    PAWN = PAWN, KNIGHT = KNIGHT, BISHOP = BISHOP, ROOK = ROOK, QUEEN = QUEEN, KING = KING,
    WHITE = WHITE, BLACK = BLACK,
    START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
}
local Position = {}
Position.__index = Position
Chess.Position = Position
ns.Chess = Chess

local FILE, RANK = {}, {}
for square = 1, 64 do
    FILE[square] = (square - 1) % 8
    RANK[square] = floor((square - 1) / 8)
end

local function buildRays(directions, maxSteps)
    local rays = {}
    for index, direction in ipairs(directions) do
        rays[index] = {}
        for square = 1, 64 do
            local ray = {}
            local file, rank = FILE[square] + direction[1], RANK[square] + direction[2]
            while #ray < maxSteps and file >= 0 and file <= 7 and rank >= 0 and rank <= 7 do
                ray[#ray + 1] = rank * 8 + file + 1
                file, rank = file + direction[1], rank + direction[2]
            end
            rays[index][square] = ray
        end
    end
    return rays
end

local DIRECTIONS = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local RAYS = {
    [KNIGHT] = buildRays({ { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 }, { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 } }, 1),
    [BISHOP] = buildRays({ unpack(DIRECTIONS, 1, 4) }, 8),
    [ROOK] = buildRays({ unpack(DIRECTIONS, 5, 8) }, 8),
    [QUEEN] = buildRays(DIRECTIONS, 8),
    [KING] = buildRays(DIRECTIONS, 1),
}
local PAWN_SOURCES = {
    [WHITE] = buildRays({ { -1, -1 }, { 1, -1 } }, 1),
    [BLACK] = buildRays({ { -1, 1 }, { 1, 1 } }, 1),
}

local function squareName(square)
    local file = FILE[square] + 1
    return FILE_LETTERS:sub(file, file) .. (RANK[square] + 1)
end

local function squareFromName(name)
    local file, rank = FILE_LETTERS:find(name:sub(1, 1), 1, true), tonumber(name:sub(2, 2))
    return file and rank and ((rank - 1) * 8 + file) or 0
end

Chess.SquareName = squareName

function Position.New(fen)
    local self = setmetatable({}, Position)
    return self:SetFEN(fen or Chess.START_FEN) and self or nil
end

function Position:SetFEN(fen)
    local placement, turn, rights, ep, half, full = fen:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s*(%d*)%s*(%d*)")
    if not placement then
        return false
    end

    local board, kings = {}, {}
    for square = 1, 64 do
        board[square] = 0
    end
    local rank, file = 7, 0
    for char in placement:gmatch(".") do
        if char == "/" then
            rank, file = rank - 1, 0
        elseif tonumber(char) then
            file = file + tonumber(char)
        else
            local kind = PIECE_LETTERS:find(char:upper(), 1, true)
            if not kind or rank < 0 or file > 7 then
                return false
            end
            local color, square = (char == char:upper()) and WHITE or BLACK, rank * 8 + file + 1
            board[square] = color * kind
            if kind == KING then
                kings[color] = square
            end
            file = file + 1
        end
    end
    if not (kings[WHITE] and kings[BLACK]) then
        return false
    end

    self.board, self.king = board, kings
    self.turn = (turn == "b") and BLACK or WHITE
    self.rights = (rights == "-") and "" or rights
    self.ep = squareFromName(ep)
    self.half, self.full = tonumber(half) or 0, tonumber(full) or 1
    return true
end

function Position:GetFEN()
    local rows = {}
    for rank = 7, 0, -1 do
        local row, gap = "", 0
        for file = 0, 7 do
            local piece = self.board[rank * 8 + file + 1]
            if piece == 0 then
                gap = gap + 1
            else
                local letter = PIECE_LETTERS:sub(abs(piece), abs(piece))
                row = row .. (gap > 0 and gap or "") .. (piece < 0 and letter:lower() or letter)
                gap = 0
            end
        end
        rows[#rows + 1] = row .. (gap > 0 and gap or "")
    end
    return ("%s %s %s %s %d %d"):format(
        table.concat(rows, "/"),
        self.turn == WHITE and "w" or "b",
        self.rights == "" and "-" or self.rights,
        self.ep > 0 and squareName(self.ep) or "-",
        self.half,
        self.full
    )
end

local function sees(board, square, rays, piece, alsoPiece)
    for index = 1, #rays do
        local ray = rays[index][square]
        for step = 1, #ray do
            local found = board[ray[step]]
            if found ~= 0 then
                if found == piece or found == alsoPiece then
                    return true
                end
                break
            end
        end
    end
    return false
end

function Position:IsAttacked(square, by)
    local board = self.board
    return sees(board, square, PAWN_SOURCES[by], by * PAWN)
        or sees(board, square, RAYS[KNIGHT], by * KNIGHT)
        or sees(board, square, RAYS[KING], by * KING)
        or sees(board, square, RAYS[BISHOP], by * BISHOP, by * QUEEN)
        or sees(board, square, RAYS[ROOK], by * ROOK, by * QUEEN)
end

function Position:InCheck()
    return self:IsAttacked(self.king[self.turn], -self.turn)
end

local function addMove(moves, from, to, piece, capture, extra)
    local move = extra or {}
    move.from, move.to, move.piece, move.capture = from, to, piece, capture
    moves[#moves + 1] = move
end

local function addPawnMove(moves, from, to, piece, capture, lastRank)
    if RANK[to] ~= lastRank then
        return addMove(moves, from, to, piece, capture)
    end
    for _, promo in ipairs(PROMOTIONS) do
        addMove(moves, from, to, piece, capture, { promo = promo })
    end
end

local function addPawnMoves(position, square, moves)
    local board, us = position.board, position.turn
    local piece = us * PAWN
    local lastRank, startRank = us == WHITE and 7 or 0, us == WHITE and 1 or 6
    local forward = square + 8 * us

    if board[forward] == 0 then
        addPawnMove(moves, square, forward, piece, 0, lastRank)
        local double = forward + 8 * us
        if RANK[square] == startRank and board[double] == 0 then
            addMove(moves, square, double, piece, 0, { double = true })
        end
    end
    for delta = -1, 1, 2 do
        local file = FILE[square] + delta
        if file >= 0 and file <= 7 then
            local target = forward + delta
            if board[target] * us < 0 then
                addPawnMove(moves, square, target, piece, board[target], lastRank)
            elseif target == position.ep then
                addMove(moves, square, target, piece, -piece, { ep = target - 8 * us })
            end
        end
    end
end

local function addRayMoves(position, square, piece, moves)
    local board, us = position.board, position.turn
    local rays = RAYS[abs(piece)]
    for index = 1, #rays do
        local ray = rays[index][square]
        for step = 1, #ray do
            local target = ray[step]
            local occupant = board[target]
            if occupant * us <= 0 then
                addMove(moves, square, target, piece, occupant)
            end
            if occupant ~= 0 then
                break
            end
        end
    end
end

local function addCastles(position, moves)
    local board, us = position.board, position.turn
    local base = us == WHITE and 0 or 56
    local king = base + 5
    if board[king] ~= us * KING or position:IsAttacked(king, -us) then
        return
    end
    for _, castle in ipairs(CASTLES) do
        local right = us == WHITE and castle.right or castle.right:lower()
        local step = castle.rookFrom > 5 and 1 or -1
        local clear = board[base + castle.rookFrom] == us * ROOK
        for offset = 5 + step, castle.rookFrom - step, step do
            clear = clear and board[base + offset] == 0
        end
        if clear and position.rights:find(right, 1, true) and not position:IsAttacked(base + castle.rookTo, -us) then
            addMove(moves, king, base + castle.kingTo, us * KING, 0, {
                castle = true,
                rookFrom = base + castle.rookFrom,
                rookTo = base + castle.rookTo,
            })
        end
    end
end

local function removeRights(position, pattern)
    if pattern then
        position.rights = position.rights:gsub(pattern, "")
    end
end

function Position:Make(move)
    local board, us = self.board, self.turn
    local undo = { ep = self.ep, half = self.half, rights = self.rights, captured = board[move.to] }

    if move.ep then
        undo.captured = board[move.ep]
        board[move.ep] = 0
    end
    board[move.from] = 0
    board[move.to] = move.promo and us * move.promo or move.piece
    if move.castle then
        board[move.rookTo], board[move.rookFrom] = board[move.rookFrom], 0
    end
    if move.piece == us * KING then
        self.king[us] = move.to
        removeRights(self, us == WHITE and "[KQ]" or "[kq]")
    end
    removeRights(self, CORNER_RIGHT[move.from])
    removeRights(self, CORNER_RIGHT[move.to])

    self.ep = move.double and (move.from + move.to) / 2 or 0
    self.half = (abs(move.piece) == PAWN or undo.captured ~= 0) and 0 or self.half + 1
    self.full = self.full + (us == BLACK and 1 or 0)
    self.turn = -us
    return undo
end

function Position:Unmake(move, undo)
    local board = self.board
    local us = -self.turn

    board[move.from] = move.piece
    board[move.to] = move.ep and 0 or undo.captured
    if move.ep then
        board[move.ep] = undo.captured
    end
    if move.castle then
        board[move.rookFrom], board[move.rookTo] = board[move.rookTo], 0
    end
    if move.piece == us * KING then
        self.king[us] = move.from
    end

    self.ep, self.half, self.rights = undo.ep, undo.half, undo.rights
    self.full = self.full - (us == BLACK and 1 or 0)
    self.turn = us
end

function Position:LegalMoves()
    local board, us = self.board, self.turn
    local pseudo = {}
    for square = 1, 64 do
        local piece = board[square]
        if piece * us > 0 then
            if abs(piece) == PAWN then
                addPawnMoves(self, square, pseudo)
            else
                addRayMoves(self, square, piece, pseudo)
            end
        end
    end
    addCastles(self, pseudo)

    local legal = {}
    for _, move in ipairs(pseudo) do
        local undo = self:Make(move)
        if not self:IsAttacked(self.king[us], -us) then
            legal[#legal + 1] = move
        end
        self:Unmake(move, undo)
    end
    return legal
end

function Position:HasMatingMaterial()
    local minors = 0
    for square = 1, 64 do
        local kind = abs(self.board[square])
        if kind == PAWN or kind == ROOK or kind == QUEEN then
            return true
        elseif kind == KNIGHT or kind == BISHOP then
            minors = minors + 1
        end
    end
    return minors > 1
end

function Position:GetStatus()
    local moves = self:LegalMoves()
    if #moves == 0 then
        return self:InCheck() and "checkmate" or "stalemate", moves
    elseif self.half >= 100 then
        return "fifty", moves
    elseif not self:HasMatingMaterial() then
        return "insufficient", moves
    end
    return nil, moves
end

function Position:ToUCI(move)
    local promo = move.promo and PIECE_LETTERS:sub(move.promo, move.promo):lower() or ""
    return squareName(move.from) .. squareName(move.to) .. promo
end

function Position:FromUCI(text)
    for _, move in ipairs(self:LegalMoves()) do
        if self:ToUCI(move) == text then
            return move
        end
    end
end

local function disambiguation(move, legal)
    local ambiguous, sameFile, sameRank = false, false, false
    for _, other in ipairs(legal) do
        if other.to == move.to and other.piece == move.piece and other.from ~= move.from then
            ambiguous = true
            sameFile = sameFile or FILE[other.from] == FILE[move.from]
            sameRank = sameRank or RANK[other.from] == RANK[move.from]
        end
    end
    local name = squareName(move.from)
    if not ambiguous then
        return ""
    elseif not sameFile then
        return name:sub(1, 1)
    elseif not sameRank then
        return name:sub(2, 2)
    end
    return name
end

function Position:ToSAN(move)
    local kind = abs(move.piece)
    local capture = move.capture ~= 0 and "x" or ""
    local text
    if move.castle then
        text = FILE[move.to] == 6 and "O-O" or "O-O-O"
    elseif kind == PAWN then
        local origin = move.capture ~= 0 and squareName(move.from):sub(1, 1) or ""
        local promo = move.promo and "=" .. PIECE_LETTERS:sub(move.promo, move.promo) or ""
        text = origin .. capture .. squareName(move.to) .. promo
    else
        text = PIECE_LETTERS:sub(kind, kind) .. disambiguation(move, self:LegalMoves()) .. capture .. squareName(move.to)
    end

    local undo = self:Make(move)
    local suffix = self:InCheck() and (#self:LegalMoves() == 0 and "#" or "+") or ""
    self:Unmake(move, undo)
    return text .. suffix
end
