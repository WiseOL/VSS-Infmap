-- Source's WORLD group ignores entity terrain. Emulate that group using a
-- player-passable engine group plus a filter which includes InfMap's ground.
local meta = FindMetaTable("Entity")
local setGroup, getGroup = meta.SetCollisionGroup, meta.GetCollisionGroup
local ground = {infmap_terrain_collider = true, infmap_planet = true, infmap_obj_collider = true}
function InfMap.WorldOnlyCollision(a, b)
    if a.InfMapWorldOnly or b.InfMapWorldOnly then
        local other = a.InfMapWorldOnly and b or a
        -- The physgun tests player/prop eligibility through ShouldCollide.
        -- Let that test proceed; PASSABLE_DOOR handles player movement natively.
        if other:IsPlayer() then return end
        return ground[other:GetClass()] == true
    end
end
function meta:GetCollisionGroup()
    if self.InfMapWorldOnly then return COLLISION_GROUP_WORLD end
    return getGroup(self)
end
function meta:SetCollisionGroup(group)
    local worldOnly = group == COLLISION_GROUP_WORLD
    self.InfMapWorldOnly = worldOnly
    if SERVER then self:SetNW2Bool("InfMapWorldOnly", worldOnly) end
    self:SetCustomCollisionCheck(true)
    setGroup(self, worldOnly and COLLISION_GROUP_PASSABLE_DOOR or group)
    self:CollisionRulesChanged()
end
if CLIENT then
    hook.Add("EntityNetworkedVarChanged", "InfMapWorldOnly", function(ent, name, _, value)
        if name ~= "InfMapWorldOnly" then return end
        ent.InfMapWorldOnly = value
        ent:SetCustomCollisionCheck(true)
        ent:CollisionRulesChanged()
    end)
else
    hook.Add("InitPostEntity", "InfMapWorldOnlyExisting", function()
        for _, ent in ipairs(ents.GetAll()) do
            if getGroup(ent) == COLLISION_GROUP_WORLD then ent:SetCollisionGroup(COLLISION_GROUP_WORLD) end
        end
    end)
end
