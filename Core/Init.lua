local ADDON_NAME, ns = ...

local DEFAULTS = { rating = 0, gamesPlayed = 0 }

function ns.Print(message)
    print("|cff33ccffChesswar|r: " .. message)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON_NAME then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")
    ChesswarDB = ChesswarDB or {}
    for key, value in pairs(DEFAULTS) do
        if ChesswarDB[key] == nil then
            ChesswarDB[key] = value
        end
    end
    ns.db = ChesswarDB
end)

SLASH_CHESSWAR1 = "/chess"
SlashCmdList["CHESSWAR"] = function()
    ns.UI.Toggle()
end
