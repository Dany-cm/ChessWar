local _, ns = ...

local Game = {}
Game.__index = Game
ns.Game = Game

local function positionKey(position)
    return (position:GetFEN():match("^(%S+ %S+ %S+ %S+)"))
end

function Game:Refresh()
    local position = self.position
    local status, legal = position:GetStatus()
    local key = positionKey(position)
    self.seen[key] = (self.seen[key] or 0) + 1
    if not status and self.seen[key] >= 3 then
        status = "repetition"
    end
    self.status, self.legal = status, legal
    self.winner = status == "checkmate" and -position.turn or nil
end

function Game.New(fen)
    local self = setmetatable({ position = ns.Chess.Position.New(fen), moves = {}, seen = {} }, Game)
    self:Refresh()
    return self
end

function Game:Play(move)
    local san = self.position:ToSAN(move)
    self.position:Make(move)
    self.moves[#self.moves + 1] = { move = move, san = san }
    self:Refresh()
end
