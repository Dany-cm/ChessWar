local _, ns = ...

local Chess, Bot = ns.Chess, ns.Bot
local WHITE, BLACK = Chess.WHITE, Chess.BLACK
local abs, max, ceil = math.abs, math.max, math.ceil

local FRAME_NAME = "ChesswarFrame"
local CELL = 48
local BOARD_X, BOARD_Y = 20, 44
local PANEL_X = BOARD_X + 8 * CELL + 16
local PANEL_WIDTH = 160
local ROW_HEIGHT = 20
local ROW_Y = BOARD_Y + 44
local FRAME_HEIGHT = BOARD_Y + 8 * CELL + 92
local MOVE_LINES = 11

local PIECE_LETTERS = { "P", "N", "B", "R", "Q", "K" }
local PROMOTION_CHOICES = { Chess.QUEEN, Chess.ROOK, Chess.BISHOP, Chess.KNIGHT }
local SIDE_NAME = { [WHITE] = "White", [BLACK] = "Black" }
local DRAW_TEXT = {
    stalemate = "Draw by stalemate",
    fifty = "Draw by the fifty-move rule",
    insufficient = "Draw: insufficient material",
    repetition = "Draw by threefold repetition",
}
local OPPONENTS = { { name = "Two players" } }
for _, level in ipairs(Bot.LEVELS) do
    OPPONENTS[#OPPONENTS + 1] = level
end
local MOVES_Y = ROW_Y + #OPPONENTS * ROW_HEIGHT + 8
local COLORS = {
    opponent = { 0.8, 0.6, 0.1, 0.35 },
    light = { 0.93, 0.84, 0.66 },
    dark = { 0.55, 0.38, 0.22 },
    whitePiece = { 1, 0.97, 0.85 },
    blackPiece = { 0.06, 0.05, 0.08 },
    selected = { 1, 0.85, 0.1, 0.55 },
    target = { 0.2, 0.8, 0.3, 0.45 },
    lastMove = { 1, 0.95, 0.3, 0.3 },
    check = { 0.9, 0.1, 0.1, 0.6 },
}

local UI = {}
ns.UI = UI

local game, frame, cells, statusText, movesText, promotionRow, opponentRows, colorButton
local selected, pending, thinking
local flipped = false
local opponent = OPPONENTS[2]
local playerColor = WHITE
local botMoveIfDue

local function squareOf(cell)
    local file, rank = cell.col, 7 - cell.row
    if flipped then
        file, rank = 7 - file, 7 - rank
    end
    return rank * 8 + file + 1
end

local function movesBetween(from, to)
    local found = {}
    for _, move in ipairs(game.legal) do
        if move.from == from and move.to == to then
            found[#found + 1] = move
        end
    end
    return found
end

local function statusLine()
    if game.status == "checkmate" then
        return ("Checkmate - %s wins"):format(SIDE_NAME[game.winner])
    elseif game.status then
        return DRAW_TEXT[game.status]
    end
    if thinking then
        return opponent.name .. " is thinking..."
    end
    return SIDE_NAME[game.position.turn] .. " to move" .. (game.position:InCheck() and " (check)" or "")
end

local function playersTurn()
    return not game.status and not thinking and (not opponent.depth or game.position.turn == playerColor)
end

local function moveListText()
    local lines = {}
    for index = 1, #game.moves, 2 do
        local black = game.moves[index + 1]
        lines[#lines + 1] = ("%d. %s %s"):format(ceil(index / 2), game.moves[index].san, black and black.san or "")
    end
    return table.concat(lines, "\n", max(1, #lines - MOVE_LINES + 1))
end

local function highlightFor(square, targets, last, checkSquare)
    if square == selected then
        return COLORS.selected
    elseif square == checkSquare then
        return COLORS.check
    elseif targets[square] then
        return COLORS.target
    elseif last and (square == last.from or square == last.to) then
        return COLORS.lastMove
    end
end

local function render()
    local position = game.position
    local last = game.moves[#game.moves]
    local checkSquare = position:InCheck() and position.king[position.turn]
    local targets = {}
    for _, move in ipairs(game.legal) do
        if move.from == selected then
            targets[move.to] = true
        end
    end

    for _, cell in ipairs(cells) do
        local square = squareOf(cell)
        local piece = position.board[square]
        local name = Chess.SquareName(square)

        cell.shade:SetColorTexture(unpack((cell.col + cell.row) % 2 == 0 and COLORS.light or COLORS.dark))
        local glow = highlightFor(square, targets, last and last.move, checkSquare)
        if glow then
            cell.glow:SetColorTexture(unpack(glow))
            cell.glow:Show()
        else
            cell.glow:Hide()
        end
        cell.piece:SetText(piece ~= 0 and PIECE_LETTERS[abs(piece)] or "")
        cell.piece:SetTextColor(unpack(piece > 0 and COLORS.whitePiece or COLORS.blackPiece))
        cell.rank:SetText(cell.col == 0 and name:sub(2, 2) or "")
        cell.file:SetText(cell.row == 7 and name:sub(1, 1) or "")
    end

    for index, row in ipairs(opponentRows) do
        if OPPONENTS[index] == opponent then
            row.mark:Show()
        else
            row.mark:Hide()
        end
    end
    colorButton:SetText("Play as: " .. SIDE_NAME[playerColor])
    statusText:SetText(statusLine())
    movesText:SetText(moveListText())
end

local function play(move)
    game:Play(move)
    selected, pending = nil, nil
    promotionRow:Hide()
    render()
    botMoveIfDue()
end

function botMoveIfDue()
    if not opponent.depth or game.status or game.position.turn == playerColor then
        return
    end
    local thinkingGame = game
    thinking = true
    render()
    Bot.Think(game.position, opponent, function(move)
        if thinkingGame == game then
            thinking = false
            play(move)
        end
    end)
end

local function choosePromotion(kind)
    for _, move in ipairs(pending) do
        if move.promo == kind then
            return play(move)
        end
    end
end

local function onCellClick(cell)
    if pending then
        selected, pending = nil, nil
        promotionRow:Hide()
        return render()
    end
    if not playersTurn() then
        return
    end

    local square = squareOf(cell)
    if selected then
        local moves = movesBetween(selected, square)
        if #moves == 1 then
            return play(moves[1])
        elseif #moves > 1 then
            pending = moves
            promotionRow:Show()
            return render()
        end
    end
    local turn = game.position.turn
    selected = game.position.board[square] * turn > 0 and square or nil
    render()
end

local function newGame()
    Bot.Cancel()
    game = ns.Game.New()
    selected, pending, thinking = nil, nil, false
    flipped = playerColor == BLACK
    promotionRow:Hide()
    render()
    botMoveIfDue()
end

local function chooseOpponent(index)
    opponent = OPPONENTS[index]
    newGame()
end

local function toggleColor()
    playerColor = -playerColor
    newGame()
end

local function createCells()
    cells = {}
    for row = 0, 7 do
        for col = 0, 7 do
            local cell = CreateFrame("Button", nil, frame)
            cell:SetSize(CELL, CELL)
            cell:SetPoint("TOPLEFT", frame, "TOPLEFT", BOARD_X + col * CELL, -(BOARD_Y + row * CELL))
            cell.col, cell.row = col, row

            cell.shade = cell:CreateTexture(nil, "BACKGROUND")
            cell.shade:SetAllPoints()
            cell.glow = cell:CreateTexture(nil, "ARTWORK")
            cell.glow:SetAllPoints()

            cell.piece = cell:CreateFontString(nil, "OVERLAY")
            cell.piece:SetFont(STANDARD_TEXT_FONT, 30, "OUTLINE")
            cell.piece:SetPoint("CENTER")
            cell.rank = cell:CreateFontString(nil, "OVERLAY")
            cell.rank:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
            cell.rank:SetPoint("TOPLEFT", 2, -2)
            cell.file = cell:CreateFontString(nil, "OVERLAY")
            cell.file:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
            cell.file:SetPoint("BOTTOMRIGHT", -2, 2)

            cell:SetScript("OnClick", onCellClick)
            cells[#cells + 1] = cell
        end
    end
end

local function createText(template, y, height)
    local text = frame:CreateFontString(nil, "OVERLAY", template)
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", PANEL_X, -y)
    text:SetSize(PANEL_WIDTH, height)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    return text
end

local function createButton(label, y, onClick)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(PANEL_WIDTH, 24)
    button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PANEL_X, y)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
end

local function createOpponentRows()
    opponentRows = {}
    for index, entry in ipairs(OPPONENTS) do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(PANEL_WIDTH, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", PANEL_X, -(ROW_Y + (index - 1) * ROW_HEIGHT))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.mark = row:CreateTexture(nil, "BACKGROUND")
        row.mark:SetAllPoints()
        row.mark:SetColorTexture(unpack(COLORS.opponent))
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 6, 0)
        row.text:SetText(entry.elo and ("%s (%d)"):format(entry.name, entry.elo) or entry.name)
        row:SetScript("OnClick", function()
            chooseOpponent(index)
        end)
        opponentRows[index] = row
    end
end

local function createPromotionRow()
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(8 * CELL, 24)
    row:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", BOARD_X, 14)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT")
    label:SetText("Promote to:")
    for index, kind in ipairs(PROMOTION_CHOICES) do
        local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        button:SetSize(40, 24)
        button:SetPoint("LEFT", row, "LEFT", 90 + (index - 1) * 44, 0)
        button:SetText(PIECE_LETTERS[kind])
        button:SetScript("OnClick", function()
            choosePromotion(kind)
        end)
    end
    row:Hide()
    return row
end

local function createFrame()
    frame = CreateFrame("Frame", FRAME_NAME, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(PANEL_X + PANEL_WIDTH + 20, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, FRAME_NAME)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Chesswar")
    CreateFrame("Button", nil, frame, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -4, -4)

    createCells()
    statusText = createText("GameFontNormalLarge", BOARD_Y, 40)
    createOpponentRows()
    movesText = createText("GameFontHighlight", MOVES_Y, FRAME_HEIGHT - 116 - MOVES_Y)
    createButton("New Game", 88, newGame)
    colorButton = createButton("", 56, toggleColor)
    createButton("Flip Board", 24, function()
        flipped = not flipped
        render()
    end)
    promotionRow = createPromotionRow()
end

function UI.Toggle()
    if not frame then
        createFrame()
        newGame()
    elseif frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
