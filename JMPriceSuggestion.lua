
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

--[[

    Sale History

 ]]

local History = {}

---
-- Create a unique enough code from the itemLink
-- Items are not unique enough, There is a big difference between a level 1 and level 50
-- So we add some more information to the code
--
-- @param itemLink
--
function History:getCodeFromItemLink(itemLink)
    return itemLink
    --    return string.format(
    --        '%d_%d_%d',
    --        GetItemLinkQuality(itemLink),
    --        GetItemLinkRequiredLevel(itemLink),
    --        GetItemLinkRequiredVeteranRank(itemLink)
    --    )
end

---
-- Get all sales matching the given store item
--
-- @param itemLink
-- @param itemId
--
function History:getSaleListFromItem(itemLink, itemId)
    -- Get sale history of this item id
    local saleList = JMGuildSaleHistoryTracker.getSalesFromItemId(itemId)
    local itemCode = History:getCodeFromItemLink(itemLink)

    -- Remove sales which are not really the same
    -- Like not having the same level etc
    -- Desided by the itemCode
    for saleIndex = #(saleList), 1, -1 do
        local sale = saleList[saleIndex]
        local saleCode = History:getCodeFromItemLink(sale.itemLink)

        if itemCode ~= saleCode then
            table.remove(saleList, saleIndex)
        end
    end

    return saleList
end

---
-- Returns sale list for the item group by guild name
--
-- @todo refactor to more global grouper (can give the property to group on)
--
-- @param saleList
--
function History:groupSaleListPerGuild(saleList)
    local guildSaleList = {}

    for _, sale in ipairs(saleList) do
        if not guildSaleList[sale.guildName] then
            guildSaleList[sale.guildName] = {}
        end

        table.insert(guildSaleList[sale.guildName], sale)
    end

    return guildSaleList
end

---
-- @param saleList
--
function History:getLastSaleTimestamp(saleList)
    local lastSaleTimestamp = 0

    for _, sale in ipairs(saleList) do
        lastSaleTimestamp = math.max(lastSaleTimestamp, sale.saleTimestamp)
    end

    return lastSaleTimestamp
end

--[[

    List of Algorithms

 ]]

local AlgorithmList = {

    -- Return the most expensive price
    ['Most expensive price'] = function(saleList)

    -- Sort on most expensive first
        table.sort(saleList, function (a, b)
            return a.pricePerPiece > b.pricePerPiece
        end)

        return saleList[1].pricePerPiece
    end,

    -- Return the cheapest price
    ['Cheapest price'] = function(saleList)

    -- Sort on most expensive first
        table.sort(saleList, function (a, b)
            return a.pricePerPiece > b.pricePerPiece
        end)

        return saleList[#saleList].pricePerPiece
    end,

    -- Return the median price
    ['Median price'] = function(saleList)

    -- Sort on most expensive first
        table.sort(saleList, function (a, b)
            return a.pricePerPiece > b.pricePerPiece
        end)

        local index = math.ceil(#saleList / 2)

        return saleList[index].pricePerPiece
    end,

    -- Return the newest price
    ['Newest price'] = function(saleList)

    -- Sort on sale timestamp
    -- The newest will now be the first sale
        table.sort(saleList, function (a, b)
            return a.saleTimestamp > b.saleTimestamp
        end)

        return saleList[1].pricePerPiece
    end,

    -- Return the average price
    ['Average price'] = function(saleList)
        local totalPrice = 0
        for _, sale in ipairs(saleList) do
            totalPrice = totalPrice + sale.pricePerPiece
        end

        return math.ceil(totalPrice / #saleList)
    end,
}

--[[

    Helper functions for the Algorithms

 ]]

local AlgorithmHelper = {}

---
-- Return list of algorithm names
-- Those can be used to for the price suggestion
--
function AlgorithmHelper:getNameList()
    local nameList = {}

    for name, _ in pairs(AlgorithmList) do
        table.insert(nameList, name)
    end

    return nameList
end

--[[

    Price Suggestor

 ]]

local Suggestor = {}

---
-- @param itemLink
--
function Suggestor:getPriceSuggestion(itemLink, algorithm)
    local _, _, _, itemId = ZO_LinkHandler_ParseLink(itemLink)
    local saleList = History:getSaleListFromItem(itemLink, itemId)

    local lastSaleTimestamp = History:getLastSaleTimestamp(saleList)
    local guildSaleList = History:groupSaleListPerGuild(saleList)

    local result = {
        hasPrice = #saleList ~= 0,
        saleCount = #saleList,
        lastSaleTimestamp = lastSaleTimestamp,
        suggestedPriceForGuild = {},
        bestPrice = {
            guildName = nil,
            pricePerPiece = nil,
        },
    }

    for guildName, saleListOfGuild in pairs(guildSaleList) do
        result.suggestedPriceForGuild[guildName] = {
            saleCount = #saleListOfGuild,
            pricePerPiece = algorithm(saleListOfGuild),
        }
    end

    if #(result.suggestedPriceForGuild) then
        local bestGuild = self:getBestGuild(result.suggestedPriceForGuild)
        result.bestPrice = result.suggestedPriceForGuild[bestGuild]
    end

    return result
end

---
-- @param itemLink
--
function Suggestor:getBestGuild(guildPriceList)
    local bestGuild
    local pricePerPiece = 0

    for guildName, priceInfo in pairs(guildPriceList) do
        if priceInfo.pricePerPiece > pricePerPiece then
            bestGuild = guildName
            pricePerPiece = priceInfo.pricePerPiece
        end
    end

    return bestGuild
end

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

    ---
    -- Returns list of algorithm names
    --
    -- @todo algorithms should be constants like events in other addons
    --
    getAlgorithms = function()
        return AlgorithmHelper:getNameList()
    end,

    ---
    --
    getPriceSuggestion = function(itemLink, algorithmName)
        if type(itemLink) ~= 'string' then
            d('Error: JMPriceSuggestion.getPriceSuggestion expects first parameter to be a string')
            return
        end

        if not AlgorithmList[algorithmName] then
            d('Error: Invalid algorithm name for JMPriceSuggestion.getPriceSuggestion')
            return
        end

        return Suggestor:getPriceSuggestion(itemLink, AlgorithmList[algorithmName])
    end,
}
