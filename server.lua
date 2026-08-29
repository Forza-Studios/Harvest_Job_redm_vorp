local Core = exports.vorp_core:GetCore()

RegisterServerEvent("coi_harvest:givePayment", function()
    local _source = source
    local User = Core.getUser(_source)
    if not User then return end

    local Character = User.getUsedCharacter
    if Character then
        local amount = math.random(200, 500) / 100
        Character.addCurrency(0, amount) -- 0 is Cash
        TriggerClientEvent("vorp:TipRight", _source, "You received $" .. string.format("%.2f", amount) .. " for harvesting", 3000)
    end
end)
