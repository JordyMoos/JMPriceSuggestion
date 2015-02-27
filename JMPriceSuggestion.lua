
---
--- JMPriceSuggestion
---

--[[

    Variable declaration

 ]]

---
-- @field name
-- @field savedVariablesName
--
local Config = {
    name = 'JMSuperDeal',
    savedVariablesName = 'JMSuperDealSavedVariables',
}

---
--
--
--function Parser:fetchGuildList()
--    for guildIndex = 1, GetNumGuilds() do
--        local id = GetGuildId(guildIndex)
--        local name = GetGuildName(id)
--
--        GuildList[guildIndex] = {
--            index = guildIndex,
--            id = id,
--            name = name,
--        }
--
--        GuildIdList[id] = GuildList[guildIndex]
--        GuildNameList[name] = GuildList[guildIndex]
--    end
--end

--[[

    Initialize

 ]]

---
-- Start of the addon
--
local function Initialize()

end

--[[

    Events

 ]]

--- Adding the initialize handler
EVENT_MANAGER:RegisterForEvent(
    Config.name,
    EVENT_ADD_ON_LOADED,
    function (event, addonName)
        if addonName ~= Config.name then
            return
        end

        Initialize()
        EVENT_MANAGER:UnregisterForEvent(Config.name, EVENT_ADD_ON_LOADED)
    end
)

--[[

    Api

 ]]

JMPriceSuggestion = {

    parse = function()
        Parser:startParsing()
    end,
}
