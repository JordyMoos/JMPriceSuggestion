
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

--    local array = {ZO_LinkHandler_ParseLink(itemLink)}
--    array[6] = 0 -- Looted from
--    array[20] = 0 -- Crafted
--    array[22] = 0 -- Stolen
--    array[23] = 0 -- Condition
--
--    return table.concat(array, '_')



--    return itemLink
---[[

    local _, setName, setBonusCount, _ = GetItemLinkSetInfo(itemLink)
    local glyphMinLevel, glyphMaxLevel, glyphMinVetLevel, glyphMaxVetLevel = GetItemLinkGlyphMinMaxLevels(itemLink)
    local _, enchantHeader, _ = GetItemLinkEnchantInfo(itemLink)
    local hasAbility, abilityHeader, _ = GetItemLinkOnUseAbilityInfo(itemLink)
    local traitType, _ = GetItemLinkTraitInfo(itemLink)
    local craftingSkillRank = GetItemLinkRequiredCraftingSkillRank(itemLink)

    local abilityInfo = abilityHeader
    if not hasAbility then
        for i = 1, GetMaxTraits() do
            local hasTraitAbility, traitAbilityDescription, _ = GetItemLinkTraitOnUseAbilityInfo(itemLink, i)
            if(hasTraitAbility) then
                abilityInfo = abilityInfo .. ':' .. traitAbilityDescription
            end
        end
    end

    return string.format(
        '%s_%s_%s_%s_%s_' .. '%s_%s_%s_%s_%s_' .. '%s_%s_%s_%s_%s_' .. '%s_%s',

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
        glyphMaxVetLevel or '',
        enchantHeader,
        traitType or '',
        setBonusCount or '',

        craftingSkillRank,
        abilityInfo
    )
---]]--
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
    local itemCode = JMItemCode.getCode(itemLink)

    -- Remove sales which are not really the same
    -- Like not having the same level etc
    -- Desided by the itemCode
    for saleIndex = #(saleList), 1, -1 do
        local sale = saleList[saleIndex]
        local saleCode = JMItemCode.getCode(sale.itemLink)

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
        local function getPrice(quantile, saleList) 
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
            
            local function getAgeWeight(sale)
                local function logWeight(hours)
                    local log = math.log(30 + hours)
                
                    return math.max(1, (40 / log / log))
                end
            
                local ageSeconds = GetTimeStamp() - sale.saleTimestamp
                local ageHours = ageSeconds / 3600
                
                return logWeight(ageHours)
            end
            
            if #saleList < 2 then
                return math.ceil(allSaleList[1].pricePerPiece * 0.9), 0
            end
            
            -- compute weights and average      
            local totalWeight = 0
            local weights = {}
            local sum = 0
            
            for i, sale in ipairs(allSaleList) do
                weights[i] = getAgeWeight(sale)
                totalWeight = totalWeight + weights[i]
                sum = sum + weights[i] * sale.pricePerPiece
            end

            local average = sum / totalWeight
            
            -- compute stddev
            local totalDist = 0
            
            for i, sale in ipairs(allSaleList) do
                local dist = average - sale.pricePerPiece
                totalDist = totalDist + weights[i] * dist * dist
            end
            
            local standardDeviation = math.sqrt(totalDist / (totalWeight - 1))

            return math.ceil(probit(1 - quantile) * standardDeviation + average), totalWeight
        end
        
        local saleProbability = 0.65
        
        local guildPrice, guildWeight = getPrice(saleProbability, guildSaleList)
        local globalPrice, _ = getPrice(saleProbability, allSaleList)
        local modifier = 1 / math.sqrt(1 + guildWeight / 2)
        
        return math.ceil(modifier * globalPrice + (1 - modifier) * guildPrice)
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

function Suggestor:adjustForCurrentListings(price, guildName, itemId)
    local itemList = JMTradingHouseSnapshot.getByGuildAndItem(guildName, itemId)
    if itemList == false then
        return price
    end

    if #itemList == 0 then
        return math.ceil(1.05 * price)
    end

    local sum = 0

    for _, item in ipairs(itemList) do
        sum = sum + item.pricePerPiece
    end

    return math.ceil(math.min(price, 0.95 * sum / #itemList))
end

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
            pricePerPiece = Suggestor:adjustForCurrentListings(pricePerPiece, guildName, itemId),
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
