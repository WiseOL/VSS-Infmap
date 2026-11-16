local gravity_convar = GetConVar("sv_gravity")

InfMap.water_height = -5000
-- InfMap renders a mesh, not a compiled brush-water volume.
InfMap.water_material = "infmap/water_warp"
InfMap.water_overlay_material = "effects/water_warp01"
if SERVER then
    -- AddCSLuaFile only sends Lua. These files are not in the original Workshop
    -- download when a later custom material is installed on the server alone.
    resource.AddSingleFile("materials/infmap/water_warp.vmt")
    resource.AddSingleFile("materials/infmap/dx80_tfwater001_normal.vtf")
end

local function inWater(pos)
    return pos[3] < InfMap.water_height
end

// water screenspace overlay
local changedWater = false
hook.Add("RenderScreenspaceEffects", "infmap_water_pp", function()
	if inWater(InfMap.unlocalize_vector(EyePos(), LocalPlayer().CHUNK_OFFSET)) then
        DrawMaterialOverlay(InfMap.water_overlay_material, 0.1)
        
        if !changedWater then
            changedWater = true
            LocalPlayer():EmitSound("Physics.WaterSplash")
            LocalPlayer():SetDSP(14, true)
        end
    elseif changedWater then
        changedWater = false
        LocalPlayer():EmitSound("Physics.WaterSplash")
        LocalPlayer():SetDSP(0, true)
    end
end)

// swim code yoinked from gwater, thanks again kodya
// player animations
hook.Add("CalcMainActivity", "infmap_water_swimming", function(ply)
	if !inWater(ply:GetPos()) or ply:IsOnGround() or ply:InVehicle() then return end
	return ACT_MP_SWIM, -1
end)

// main movement
hook.Add("Move", "infmap_water_swimming", function(ply, move)
    if !inWater(ply:GetPos()) then return end

	local vel = move:GetVelocity()
	local ang = move:GetMoveAngles()

	local acel =
	(ang:Forward() * move:GetForwardSpeed()) +
	(ang:Right() * move:GetSideSpeed()) +
	(ang:Up() * move:GetUpSpeed())

	local aceldir = acel:GetNormalized()
	local acelspeed = math.min(acel:Length(), ply:GetMaxSpeed())
	acel = aceldir * acelspeed * 2

	if bit.band(move:GetButtons(), IN_JUMP) ~= 0 then
	    acel.z = acel.z + ply:GetMaxSpeed()
	end

	vel = vel + acel * FrameTime()
	vel = vel * (1 - FrameTime() * 2)

	local pgrav = ply:GetGravity() == 0 and 1 or ply:GetGravity()
	local gravity = pgrav * gravity_convar:GetFloat() * 0.5
	vel.z = vel.z + FrameTime() * gravity

	move:SetVelocity(vel * 0.99)
end)

// secondary, final movement
hook.Add("FinishMove", "infmap_water_swimming", function(ply, move)
	if !inWater(ply:GetPos()) then return end
	local vel = move:GetVelocity()
	local pgrav = ply:GetGravity() == 0 and 1 or ply:GetGravity()
	local gravity = pgrav * gravity_convar:GetFloat() * 0.5

	vel.z = vel.z + FrameTime() * gravity
	move:SetVelocity(vel)
end)

// serverside stuff now
if CLIENT then
    local waterMatrix1 = Matrix()
    waterMatrix1:SetScale(Vector(100000, 100000, 1))

    local waterMatrix2 = Matrix()
    waterMatrix2:SetScale(Vector(1000000, 1000000, 1))

    local uvscale = 1000
    local waterMesh = Mesh()
    waterMesh:BuildFromTriangles({
        {pos = Vector(-1, -1, 0), u = 0, v = uvscale},
        {pos = Vector(1, 1, 0), u = uvscale, v = 0},
        {pos = Vector(1, -1, 0), u = uvscale, v = uvscale},

        {pos = Vector(-1, -1, 0), u = 0, v = uvscale},
        {pos = Vector(-1, 1, 0), u = 0, v = 0},
        {pos = Vector(1, 1, 0), u = uvscale, v = 0},

        {pos = Vector(-1, -1, 0), u = 0, v = uvscale},
        {pos = Vector(1, -1, 0), u = uvscale, v = uvscale},
        {pos = Vector(1, 1, 0), u = uvscale, v = 0},

        {pos = Vector(-1, -1, 0), u = 0, v = uvscale},
        {pos = Vector(1, 1, 0), u = uvscale, v = 0},
        {pos = Vector(-1, 1, 0), u = 0, v = 0},
    })

    local water = Material(InfMap.water_material)
    local normal = not water:IsError() and water:GetTexture("$normalmap")
    if water:IsError() or not normal or normal:IsError() or normal:IsErrorTexture() then
        -- Built-in fallback also works when clients block server downloads.
        water = Material("effects/water_warp01")
        print("[InfMap water] Missing infmap/water_warp; using built-in refraction fallback.")
    end
    hook.Add("PreDrawTranslucentRenderables", "infmap_water_draw", function(depth, sky)
        if depth or sky or water:IsError() then return end
        local co = Vector(LocalPlayer().CHUNK_OFFSET)
        co[1] = 0
        co[2] = 0
        if co[3] > InfMap.render_max_height then return end

        local zfighting_offset = math.max(LocalPlayer().CHUNK_OFFSET[3] - 20, 0) * 900
        local water_height = Vector(0, 0, InfMap.water_height - zfighting_offset)
        waterMatrix1:SetTranslation(InfMap.unlocalize_vector(water_height, -co))
        waterMatrix2:SetTranslation(InfMap.unlocalize_vector(water_height * 1.1, -co))
        -- Capture once for both surface draws, never in the depth/sky passes.
        render.UpdateRefractTexture()
        render.SetMaterial(water)

        cam.PushModelMatrix(waterMatrix1)
            waterMesh:Draw()
        cam.PopModelMatrix()

        if InfMap.unlocalize_vector(EyePos(), LocalPlayer().CHUNK_OFFSET)[3] < water_height[3] then return end

        cam.PushModelMatrix(waterMatrix2)
            waterMesh:Draw()
        cam.PopModelMatrix()
    end)
    return 
end

hook.Add("PlayerFootstep", "infmap_water_footsteps", function(ply, pos, foot, sound, volume, rf)
    if inWater(ply:GetPos()) then 
        ply:EmitSound(foot == 0 and "Water.StepLeft" or "Water.StepRight", nil, nil, volume, CHAN_BODY)     // volume doesnt work for some reason.. oh well
        return true
    end
end )

// no fall damage in fake water
hook.Add("GetFallDamage", "infmap_water_falldmg", function(ply, speed)
    // for some reason player position isnt fully accurate when this is called
    local tr = util.TraceHull({
        start = ply:GetPos(),
        endpos = ply:GetPos() + ply:GetVelocity(),
        maxs = ply:OBBMaxs(),
        mins = ply:OBBMins(),
        filter = ply
    })
    if tr.Hit and inWater(tr.HitPos) then return 0 end
end)


if SERVER then
    local IsValid = IsValid
    local positions = {}
    -- GetBuoyancyRatio is absent on some GMod branches. Track explicit tool
    -- values through the setter as well, without changing its native behavior.
    local physMeta = FindMetaTable("PhysObj")
    local explicitRatios = setmetatable({}, {__mode = "k"})
    local toolEntities = setmetatable({}, {__mode = "k"})
    local nativeSetRatio = physMeta.SetBuoyancyRatio
    if nativeSetRatio then
        function physMeta:SetBuoyancyRatio(value)
            nativeSetRatio(self, value)
            explicitRatios[self] = value
            local entity = self.GetEntity and self:GetEntity()
            if IsValid(entity) then toolEntities[entity] = true end
        end
    end
    local function BuoyancyRatio(phys, prop)
        local ratio
        -- Improved Buoyancy Tool stores a signed multiplier on the entity;
        -- duplicator stores percentage units. Survive PhysicsInit/recreation
        -- without waiting for another physgun drop to call the native setter.
        if prop and prop:GetClass() ~= "acf_buoyancy" then
            ratio = prop.BuoyancyRatio
            local data = prop.EntityMods and prop.EntityMods.buoyancy
            if ratio == nil and data then ratio = tonumber(data.Ratio) and tonumber(data.Ratio) / 100 end
        end
        if ratio == nil then ratio = explicitRatios[phys] end
        if ratio == nil and phys.GetBuoyancyRatio then ratio = phys:GetBuoyancyRatio() end
        if type(ratio) ~= "number" then return end
        if ratio ~= ratio or math.abs(ratio) == math.huge then return 0 end
        return ratio
    end
    local function RegisterToolEntities()
        for _, entity in ipairs(ents.GetAll()) do
            if entity.BuoyancyRatio ~= nil or entity.EntityMods and entity.EntityMods.buoyancy then
                toolEntities[entity] = true
            end
        end
    end
    hook.Add("InitPostEntity", "InfMapWaterToolEntities", RegisterToolEntities)
    hook.Add("PostCleanupMap", "InfMapWaterToolEntities", RegisterToolEntities)
    -- One cubic Source inch displaces 0.016387064 kg of fresh water.
    -- Collision volume determines lift; changing mass no longer creates lift.
    local waterDensity = 1000 * 0.0254 ^ 3
    local navalDrag = CreateConVar("infmap_water_naval_drag", "0.15", FCVAR_ARCHIVE,
        "Horizontal naval-craft damping rate per second; lower permits easier waterjet propulsion.", 0, 5)
    hook.Add("Think", "infmap_water_buoyancy", function()
        local waterHeight = InfMap.water_height
        local dt = engine.TickInterval()
        local gravity = math.abs(physenv.GetGravity().z)
        local entities = ents.FindByClass("prop_*")
        -- VSS compartments set their ratio through their own Think, Wire and
        -- damage paths. Add this class explicitly; never override those paths.
        for _, compartment in ipairs(ents.FindByClass("acf_buoyancy")) do
            entities[#entities + 1] = compartment
        end
        -- Share a single heave-damping budget across compartments on a boat.
        -- Using each compartment's own mass underdamps a loaded craft; using
        -- the full boat mass for every compartment would multiply damping.
        local groups, compartmentGroups = {}, {}
        for _, entity in ipairs(entities) do
            if entity:GetClass() == "acf_buoyancy" then
                local base = ACF and ACF.GetEntityBaseplate and ACF.GetEntityBaseplate(entity)
                local body = entity:GetPhysicsObject()
                if IsValid(base) and IsValid(body) and body:IsMoveable()
                    and not (entity.WaterLevel and entity:WaterLevel() > 0) then
                    local low, high = entity:WorldSpaceAABB()
                    local ratio = BuoyancyRatio(body, entity) or 0
                    if low.z < waterHeight and ratio > 0 then
                        local stiffness = (entity.MaxBuoyancyMass or 0) * ratio * 0.6 * gravity / math.max(high.z - low.z, 1)
                        local group = groups[base]
                        if not group then
                            local contraption = base.CFW_GetContraption and base:CFW_GetContraption()
                            local total = contraption and contraption.totalMass
                            local basePhys = base.GetPhysicsObject and base:GetPhysicsObject()
                            if type(total) ~= "number" or total ~= total or total <= 0 or total == math.huge then
                                total = IsValid(basePhys) and basePhys:GetMass() or 0
                                group = {mass=total, fallback=true, stiffness=0}
                            else group = {mass=total, stiffness=0} end
                            groups[base] = group
                        end
                        if group.fallback then group.mass = group.mass + body:GetMass() end
                        group.stiffness = group.stiffness + stiffness
                        compartmentGroups[entity] = {group=group, stiffness=stiffness}
                    end
                end
            end
        end
        local seen = {}
        for _, entity in ipairs(entities) do seen[entity] = true end
        for entity in pairs(toolEntities) do
            if not IsValid(entity) then toolEntities[entity] = nil
            elseif not seen[entity] then entities[#entities + 1] = entity seen[entity] = true end
        end
        for _, prop in ipairs(entities) do
            if prop.IsPlayer and prop:IsPlayer() or prop.IsNPC and prop:IsNPC() then continue end
            local phys = prop:GetPhysicsObject()
            if inWater(prop:GetPos()) and prop:IsOnFire() then prop:Extinguish() end
            if !phys:IsValid() or !phys:IsMoveable() then continue end
            -- Native brush water already supplies forces. Never double them.
            if prop.WaterLevel and prop:WaterLevel() > 0 then continue end
            local worldMins, worldMaxs = prop:WorldSpaceAABB()
            if worldMins.z >= waterHeight then continue end

            local ratio = BuoyancyRatio(phys, prop)
            local airboat = prop:GetClass() == "prop_vehicle_airboat"
            -- HL2's airboat normally floats through its native vehicle water
            -- controller. Its hull volume/engine ratio alone is not a substitute.
            if airboat and explicitRatios[phys] == nil and prop.BuoyancyRatio == nil
                and not (prop.EntityMods and prop.EntityMods.buoyancy) then ratio = 1 end
            local compartment = prop:GetClass() == "acf_buoyancy"
            if compartment then
                local base = ACF and ACF.GetEntityBaseplate and ACF.GetEntityBaseplate(prop)
                local naval = ACF and ACF.Classes and ACF.Classes.GetTypeByName("ACF.Baseplates.NavalVehicle")
                local kind = IsValid(base) and base:ACF_GetUserVar("BaseplateType")
                if not naval or not kind or kind:GetType() ~= naval then continue end
                -- Wait for the fork to set a ratio; zero/disabled compartments
                -- still experience water drag, but never supply displacement.
                ratio = ratio or 0
            elseif ratio == nil then ratio = 1 end
            local mins, maxs = prop:OBBMins(), prop:OBBMaxs()
            if airboat then
                -- Exclude the tall fan/seat from the flotation sample region.
                maxs = Vector(maxs.x, maxs.y, mins.z + (maxs.z - mins.z) * 0.45)
            end
            local volume = phys:GetVolume()
            if not volume or volume <= 0 then
                volume = math.abs((maxs.x - mins.x) * (maxs.y - mins.y) * (maxs.z - mins.z))
            end
            if volume ~= volume or volume == math.huge then continue end
            local mass = phys:GetMass()
            if mass <= 0 then continue end
            -- VSS maps 100% to ratio 100/60, i.e. native's 0.6
            -- scale. Use its published capacity for the compartment volume.
            local capacity = compartment and prop.MaxBuoyancyMass or volume * waterDensity
            capacity = capacity or 0
            if airboat then capacity = mass * 2 / 0.6 end
            local lift = capacity * ratio * 0.6 * gravity * dt / 8
            -- Eight equal-volume cells, sampled at their centers. Smooth cell
            -- coverage avoids suddenly enabling a whole corner at the waterline.
            local center = (mins + maxs) * 0.5
            local quarter = (maxs - mins) * 0.25
            local cellHeight = math.max((worldMaxs.z - worldMins.z) * 0.5, 0.01)
            local drag = (1 - math.exp(-(airboat and 0.5 or 2) * dt)) * mass / 8
            local horizontalDrag = drag
            -- Keep heave/roll damping independent from forward resistance.
            -- Previously every wet hull prop lost ~86% of horizontal velocity
            -- per second from our artificial 2/s drag, even without a load.
            local base = ACF and ACF.GetEntityBaseplate and ACF.GetEntityBaseplate(prop)
            if IsValid(base) then
                local naval = ACF.Classes and ACF.Classes.GetTypeByName("ACF.Baseplates.NavalVehicle")
                local kind = base:ACF_GetUserVar("BaseplateType")
                if naval and kind and kind:GetType() == naval then
                    horizontalDrag = (1 - math.exp(-navalDrag:GetFloat() * dt)) * mass / 8
                end
            end
            local index = 0
            for x = -1, 1, 2 do
                for y = -1, 1, 2 do
                    for z = -1, 1, 2 do
                        index = index + 1
                        positions[index] = prop:LocalToWorld(center + Vector(quarter.x * x, quarter.y * y, quarter.z * z))
                    end
                end
            end
            if airboat then
                local low, high = math.huge, -math.huge
                for _, point in ipairs(positions) do
                    low, high = math.min(low, point.z), math.max(high, point.z)
                end
                cellHeight = math.max(high - low, 0.01)
            end
            local coverage = 0
            for _, point in ipairs(positions) do
                coverage = coverage + math.Clamp(0.5 + (waterHeight - point.z) / cellHeight, 0, 1) / 8
            end
            local verticalDrag = drag
            local entry = compartmentGroups[prop]
            if airboat and coverage > 0 then
                local stiffness = capacity * math.abs(ratio) * 0.6 * gravity / math.max(cellHeight * 2, 1)
                local rate = 2 * math.sqrt(stiffness / mass)
                verticalDrag = mass * (1 - math.exp(-rate * dt)) / math.max(coverage, 0.05) / 8
            elseif compartment and coverage > 0 and entry and entry.group.stiffness > 0 then
                local group = entry.group
                local effectiveMass = math.max(group.mass, mass)
                local rate = 2 * math.sqrt(group.stiffness / effectiveMass)
                local budget = effectiveMass * (1 - math.exp(-rate * dt))
                -- Normalize over the wet points. Fade at first contact rather
                -- than dividing by a vanishing wet fraction on water entry.
                verticalDrag = budget * (entry.stiffness / group.stiffness) / math.max(coverage, 0.05) / 8
            end
            for _, point in ipairs(positions) do
                local wet = math.Clamp(0.5 + (waterHeight - point.z) / cellHeight, 0, 1)
                if wet > 0 then
                    -- Point velocity includes rotation. Opposing it underwater
                    -- damps rocking through physical torque instead of directly
                    -- overwriting angular velocity. InfMap detours these APIs
                    -- to translate global positions to native chunk coordinates.
                    local velocity = phys:GetVelocityAtPoint(point)
                    local impulse = velocity * (-horizontalDrag * wet)
                    impulse.z = (lift - velocity.z * verticalDrag) * wet
                    phys:ApplyForceOffset(impulse, point)
                end
            end
        end
    end)
end
