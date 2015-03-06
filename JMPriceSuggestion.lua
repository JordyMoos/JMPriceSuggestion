
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

--    return itemLink

    local _, setName = GetItemLinkSetInfo(itemLink)
    local glyphMinLevel, glyphMaxLevel, glyphMinVetLevel, glyphMaxVetLevel = GetItemLinkGlyphMinMaxLevels(itemLink)
    return string.format(
        '%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s',
        GetItemLinkQuality(itemLink),
        GetItemLinkRequiredLevel(itemLink),
        GetItemLinkRequiredVeteranRank(itemLink),
        GetItemLinkWeaponPower(itemLink),
        GetItemLinkArmorRating(itemLink),
        GetItemLinkValue(itemLink),
        GetItemLinkMaxEnchantCharges(itemLink),
        setName,
        glyphMinLevel or '',
        glyphMaxLevel or '',
        glyphMinVetLevel or '',
        glyphMaxVetLevel or ''
    )
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

    Algorithms

 ]]

---
-- List of possible algorithms
--
local Algorithms = {
    MOST_EXPENSIVE = 'Most Expensive',
    CHEAPEST = 'Cheapest',
    MEDIAN = 'Median',
    NEWEST = 'Newest',
    AVERAGE = 'Average',
    NORMAL = 'Normal',
}


local AlgorithmFunctionList = {

    ---
    -- Return the most expensive price
    --
    [Algorithms.MOST_EXPENSIVE] = function(saleList)
        table.sort(saleList, function (a, b)
            return a.pricePerPiece > b.pricePerPiece
        end)

        return saleList[1].pricePerPiece, saleList[1].saleTimestamp
    end,

    ---
    -- Return the cheapest price
    --
    [Algorithms.CHEAPEST] = function(saleList)
        table.sort(saleList, function (a, b)
            return a.pricePerPiece > b.pricePerPiece
        end)

        return saleList[#saleList].pricePerPiece, saleList[#saleList].saleTimestamp
    end,

    ---
    -- Return the median price
    --
    [Algorithms.MEDIAN] = function(saleList)
        table.sort(saleList, function (a, b)
            return a.pricePerPiece > b.pricePerPiece
        end)

        local index = math.ceil(#saleList / 2)

        return saleList[index].pricePerPiece, saleList[index].saleTimestamp
    end,

    ---
    -- Return the newest price
    --
    [Algorithms.NEWEST] = function(saleList)
        table.sort(saleList, function (a, b)
            return a.saleTimestamp > b.saleTimestamp
        end)

        return saleList[1].pricePerPiece, saleList[1].saleTimestamp
    end,

    ---
    -- Return the average price
    --
    [Algorithms.AVERAGE] = function(saleList)
        local totalPrice = 0
        for _, sale in ipairs(saleList) do
            totalPrice = totalPrice + sale.pricePerPiece
        end

        return math.ceil(totalPrice / #saleList)
    end,

    ---
    -- Marcus' normal
    --
    [Algorithms.NORMAL] = function(guildSaleList, allSaleList)
        local function probit(x)
            local function inverseError(x)
                local a = 0.147

                if x == 0 then
                    return 0
                end

                local log = math.log(1 - x * x)
                local log_div_2 = log / 2
                local b = log_div_2 + 2 / math.pi / a
                local first_root = math.sqrt(b * b - log / 2)
                local second_root = math.sqrt(first_root - b)

                if x > 0 then
                    return second_root
                end

                return -1 * second_root
            end

            return (inverseError(x * 2 - 1) * math.sqrt(2))
        end

        local saleProbability = 0.8
        local saleCount = #allSaleList
        local sum = 0
        local squareSum = 0

        if saleCount < 2 then
            return math.ceil(allSaleList[1].pricePerPiece * 0.9)
        end

        for _, sale in ipairs(allSaleList) do
            sum = sum + sale.pricePerPiece
            squareSum = squareSum + (sale.pricePerPiece * sale.pricePerPiece)
        end

        local average = sum / saleCount
        local variance = (saleCount * squareSum - sum * sum) / saleCount / (saleCount - 1)
        local standardDeviation = math.sqrt(variance)
--        d('stdev: ' .. standardDeviation)
--        d('avg: ' .. average)
--        d('probit: ' .. probit(1 - saleProbability))

        return math.ceil(probit(1 - saleProbability) * standardDeviation + average)
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

    for name, _ in pairs(AlgorithmFunctionList) do
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
        hasPrice = #saleList > 0,
        saleCount = #saleList,
        lastSaleTimestamp = lastSaleTimestamp,
        suggestedPriceForGuild = {},
        bestPrice = {
            guildName = nil,
            saleCount = nil,
            pricePerPiece = nil,
        },
    }

    for guildName, saleListOfGuild in pairs(guildSaleList) do
        local pricePerPiece, saleTimestamp = algorithm(saleListOfGuild, saleList)
        result.suggestedPriceForGuild[guildName] = {
            saleCount = #saleListOfGuild,
            pricePerPiece = pricePerPiece,
            saleTimestamp = saleTimestamp,
        }
    end

    if result.hasPrice then
        local bestGuild = self:getBestGuild(result.suggestedPriceForGuild)
        result.bestPrice.guildName = bestGuild
        result.bestPrice.saleCount = result.suggestedPriceForGuild[bestGuild].saleCount
        result.bestPrice.pricePerPiece = result.suggestedPriceForGuild[bestGuild].pricePerPiece
        result.bestPrice.saleTimestamp = result.suggestedPriceForGuild[bestGuild].saleTimestamp
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
    function (_, addonName)
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
    -- Constants of possible events
    --
    algorithms = Algorithms,

    ---
    --
    getPriceSuggestion = function(itemLink, algorithmName)
        if type(itemLink) ~= 'string' then
            d('Error: JMPriceSuggestion.getPriceSuggestion expects first parameter to be a string')
            return
        end

        if not AlgorithmFunctionList[algorithmName] then
            d('Error: Invalid algorithm for JMPriceSuggestion.getPriceSuggestion')
            return
        end

        return Suggestor:getPriceSuggestion(itemLink, AlgorithmFunctionList[algorithmName])
    end,
}
