-- InfMap-only crew acceleration: differentiate physical point velocities,
-- rather than twice differentiating large global position coordinates.
local states = setmetatable({}, {__mode = "k"})
local crews = setmetatable({}, {__mode = "kv"})
local function PointVelocity(crew, dt, previous)
    local model = crew.CrewModel
    if not model or not model.ScanOffsetL then return end
    local point, root = Vector(model.ScanOffsetL), crew
    -- Compose local transforms explicitly: cached child world transforms can
    -- temporarily lag a parent's Source-local teleport.
    for depth = 1, 64 do
        local parent = root:GetParent()
        if not IsValid(parent) then break end
        point = LocalToWorld(point, angle_zero, root:GetLocalPos(), root:GetLocalAngles())
        root = parent
        if depth == 64 then return end
    end
    local phys = root:GetPhysicsObject()
    if not IsValid(phys) or not phys.InfMap_GetVelocityAtPoint or not root.InfMap_LocalToWorld then return end
    local velocity = phys:InfMap_GetVelocityAtPoint(root:InfMap_LocalToWorld(point))
    if previous and previous.root == root then
        -- Crew may rotate/move relative to the body (e.g. in a turret).
        local relative = (point - previous.point) / dt
        velocity = velocity + LocalToWorld(relative, angle_zero, vector_origin, root:GetAngles())
    end
    return velocity, root, point
end

local function Install()
    if not InfMap or not InfMap.localize_vector or not ACF or not ACF.UpdateGForceTracker then return end
    if ACF.InfMapCrewGForce then return true end
    local stored = scripted_ents.GetStored("acf_crew")
    local methods = stored and stored.t
    if not methods or not methods.EnforceGForces then return end
    local originalUpdate, originalEnforce = ACF.UpdateGForceTracker, methods.EnforceGForces
    methods.EnforceGForces = function(self, ...)
        if self.GForceTracker then crews[self.GForceTracker] = self end
        return originalEnforce(self, ...)
    end
    ACF.UpdateGForceTracker = function(tracker, newPos, sampleRate, ...)
        local crew = tracker and crews[tracker]
        if not IsValid(crew) then return originalUpdate(tracker, newPos, sampleRate, ...) end
        local dt = engine.TickInterval() * math.max(tonumber(sampleRate) or 1, 1)
        local previous = states[tracker]
        local velocity, root, point = PointVelocity(crew, dt, previous)
        if not velocity then
            states[tracker] = nil
            return originalUpdate(tracker, newPos, sampleRate, ...)
        end
        -- Prime on first sample/reparent, but do not suppress samples simply
        -- because the chunk changed. Real impacts at boundaries still count.
        local acceleration = previous and previous.root == root
            and (velocity - previous.velocity) / dt or Vector()
        states[tracker] = {root = root, point = point, velocity = velocity}
        if newPos then tracker.Pos:Set(newPos) tracker.LastPos:Set(newPos) end
        tracker.Vel:Set(velocity) tracker.LastVel:Set(velocity)
        tracker.Acc:Set(acceleration) tracker.LastAcc:Set(acceleration)
        local gravity = math.abs(ACF.Gravity.z)
        if gravity == 0 then return 0 end
        return acceleration:Length() / gravity
    end
    ACF.InfMapCrewGForce = true
    print("[ACF InfMap] Crew G-force point-velocity tracking installed.")
    return true
end
hook.Add("InitPostEntity", "ACF_InfMapCrewGForce", Install)
hook.Add("ACF_OnLoadAddon", "ACF_InfMapCrewGForce", Install)
timer.Simple(0, Install)
timer.Create("ACF_InfMapCrewGForceStartup", 1, 30, function()
    if Install() then timer.Remove("ACF_InfMapCrewGForceStartup") end
end)
