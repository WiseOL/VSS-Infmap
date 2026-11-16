-- Coalesce terrain/planet occupancy checks for all parts moved in a tick.
local pending, scheduled = {}, false
function InfMap.QueueColliderCleanup(colliders, chunk)
    if not chunk then return end
    local key = InfMap.ezcoord(chunk)
    if not IsValid(colliders[key]) then return end
    pending[colliders] = pending[colliders] or {}
    pending[colliders][key] = true
    if scheduled then return end
    scheduled = true
    timer.Simple(0, function()
        local batch = pending
        pending, scheduled = {}, false
        local wanted, occupied = {}, {}
        for _, keys in pairs(batch) do for k in pairs(keys) do wanted[k] = true end end
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and ent.CHUNK_OFFSET and not InfMap.filter_entities(ent) and ent:IsSolid() then
                local k = InfMap.ezcoord(ent.CHUNK_OFFSET)
                if wanted[k] then occupied[k] = true end
            end
        end
        for colliders, keys in pairs(batch) do
            for k in pairs(keys) do
                if not occupied[k] then
                    local collider = colliders[k]
                    colliders[k] = nil
                    SafeRemoveEntity(collider)
                end
            end
        end
    end)
end
