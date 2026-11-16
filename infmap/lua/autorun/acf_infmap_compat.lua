-- InfMap (Mee's chunk_size/localize_vector API) + ACF 3 compatibility.
if SERVER then AddCSLuaFile() end
print("[ACF InfMap v37] Autorun file loaded (" .. (SERVER and "server" or "client") .. ").")

local function MissingDependencies()
    if not InfMap then return "InfMap is not active. Load an InfMap map and check that InfMap itself is installed." end
    if not InfMap.localize_vector then return "InfMap.localize_vector is missing; this InfMap version uses a different API." end
    if not ACF then return "ACF is not loaded. Check ACF installation and its dependencies." end
    if not ACF.Utilities or not ACF.Utilities.Effects then return "ACF.Utilities.Effects is missing; this ACF version is not supported by this patch." end
    if SERVER and (not InfMap.TraceHull or not InfMap.TraceEntity) then return "InfMap server trace functions are not ready." end
end

local function Install()
    if MissingDependencies() then return end
    if ACF.InfMapCompatibility then return end
    ACF.InfMapCompatibility = true
    ACF.InfMapCompatibilityRevision = 37
    ACF.InfMapAuthoritativeEffects = true

    if SERVER then
        include("autorun/!infmap_acf_traces.lua")
        local Scoped = InfMap.ACFScoped
        -- ACF.trace is shared by sensors, tools and other addons: leave it intact.
        if ACF.Ballistics then
            for _, name in ipairs({"DoBulletsFlight", "DigTrace", "PenetrateMapEntity", "PenetrateGround", "ResolveNextObstacle", "BeginPenetration"}) do
                local original = ACF.Ballistics[name]
                if isfunction(original) then ACF.Ballistics[name] = Scoped(original) end
            end
            -- Keep command-clock simulation, but use the chunk-safe effect
            -- channel for everyone. Native prediction packets quantize origins.
            local send=ACF.Ballistics.BulletClient
            if isfunction(send) then
                ACF.Ballistics.BulletClient=function(bullet,...)
                    local predicted=bullet.Predictable
                    bullet.Predictable=false
                    local args={n=select("#",...),...}
                    local ok,err=pcall(send,bullet,(unpack or table.unpack)(args,1,args.n))
                    bullet.Predictable=predicted
                    if not ok then error(err,0) end
                end
            end
        end
        util.AddNetworkString("ACF_InfMapBulletRemove")
        if ACF.Ballistics and isfunction(ACF.Ballistics.RemoveBullet) then
            local remove = ACF.Ballistics.RemoveBullet
            ACF.Ballistics.RemoveBullet = function(bullet, ...)
                if bullet and not bullet.Removed and not bullet.NoEffect and bullet.Index and not ACF.InfMapResettingBallistics then
                    net.Start("ACF_InfMapBulletRemove")
                    net.WriteUInt(bullet.Index, 16)
                    local stats = ACF.InfMapNetworkStats
                    if stats then
                        stats.removals = (stats.removals or 0) + 1
                        if net.BytesWritten then stats.bytes = stats.bytes + net.BytesWritten() end
                    end
                    net.Broadcast()
                end
                return remove(bullet, ...)
            end
        end
        util.AddNetworkString("ACF_InfMapEffect")
        util.AddNetworkString("ACF_InfMapBullet")
    end

    local effects = ACF.Utilities.Effects
    if SERVER then
        local originalFactory = effects.CreateEffect
        local compactFields = {DamageType=true, Scale=true, Attachment=true, Entity=true, EntIndex=true, InfMapAmmo=true}
        local stats = {compact = 0, generic = 0, bytes = 0}
        ACF.InfMapNetworkStats = stats
        local function Deliver(filter)
            if net.BytesWritten then stats.bytes = stats.bytes + net.BytesWritten() end
            if filter ~= nil and not isbool(filter) then net.Send(filter) else net.Broadcast() end
        end
        local function SendEffect(name, values, override, filter)
            -- Engine effect networking quantizes positions. Send world coordinates
            -- as floats, and create the effect locally in each viewer's frame.
            local payload = {}
            for k, v in pairs(values) do if k ~= "Origin" and k ~= "Start" then payload[k] = v end end
            if payload.Flags == 0 then payload.Flags = nil end
            local suffix = ACF.GetCrateNWSuffix and ACF.GetCrateNWSuffix(values.Flags or 0) or ""
            local crate = values.Entity or values.EntIndex
            if type(crate) == "number" then crate = Entity(crate) end
            if string.lower(name) == "acf_bullet_effect" and (values.Scale or 0) == 0 and IsValid(crate) then
                payload.InfMapAmmo = {AmmoType = crate:GetNW2String("AmmoType" .. suffix, "ACF.Ammunition.AP"),
                    Caliber = crate:GetNW2Float("Caliber" .. suffix, 10), RoundMass = crate:GetNW2Float("ProjMass" .. suffix, 10),
                    FillerMass = crate:GetNW2Float("FillerMass" .. suffix), WPMass = crate:GetNW2Float("WPMass" .. suffix)}
            end
            local compact = string.lower(name) == "acf_bullet_effect"
                and type(values.DamageType) == "number" and values.DamageType >= 0 and values.DamageType <= 65535
                and values.DamageType % 1 == 0 and (values.Scale or 0) % 1 == 0
                and (values.Scale or 0) >= 0 and (values.Scale or 0) <= 3
            for key in pairs(payload) do if not compactFields[key] then compact = false break end end
            if compact then
                stats.compact = stats.compact + 1
                local hit = values.Scale or 0
                net.Start("ACF_InfMapBullet")
                net.WriteUInt(values.DamageType, 16)
                net.WriteUInt(hit, 2)
                net.WriteBool((values.Attachment or 0) > 0)
                net.WriteBool(override ~= false)
                for _, field in ipairs({"Origin", "Start"}) do
                    local v = values[field] or Vector()
                    net.WriteFloat(v.x) net.WriteFloat(v.y) net.WriteFloat(v.z)
                end
                if hit == 0 then
                    net.WriteEntity(IsValid(crate) and crate or NULL)
                    local ammo = payload.InfMapAmmo
                    net.WriteBool(ammo ~= nil)
                    if ammo then
                        net.WriteString(ammo.AmmoType)
                        net.WriteFloat(ammo.Caliber) net.WriteFloat(ammo.RoundMass)
                        net.WriteFloat(ammo.FillerMass) net.WriteFloat(ammo.WPMass)
                    end
                end
                Deliver(filter)
                return
            end
            stats.generic = stats.generic + 1
            net.Start("ACF_InfMapEffect")
            net.WriteString(name)
            for _, field in ipairs({"Origin", "Start"}) do
                local v = values[field] or Vector()
                net.WriteFloat(v.x) net.WriteFloat(v.y) net.WriteFloat(v.z)
            end
            net.WriteTable(payload)
            net.WriteBool(override ~= false)
            net.WriteBool(string.lower(name) ~= "acf_bullet_effect" and values.Start ~= nil)
            Deliver(filter)
        end
        effects.CreateEffect = function(name, values, override, filter)
            if not name or not values then return end
            if string.sub(string.lower(name), 1, 4) ~= "acf_" then
                return originalFactory(name, values, override, filter)
            end
            local newName, newValues = hook.Run("ACF_PreCreateEffect", name, values)
            SendEffect(newName or name, newValues or values, override, filter)
        end

        -- Older ACF versions and some current paths call util.Effect directly.
        -- Catch those too; unrelated addon effects retain their original path.
        local engineEffect = util.Effect
        local fields = {"Origin", "Start", "Normal", "Angles", "Flags", "Entity",
            "Scale", "Magnitude", "Radius", "Attachment", "SurfaceProp",
            "MaterialIndex", "DamageType", "HitBox", "Color"}
        util.Effect = function(name, data, override, filter)
            if not name or not data then return engineEffect(name, data, override, filter) end
            local acfEffect = string.sub(string.lower(name), 1, 4) == "acf_"
            if not acfEffect then return engineEffect(name, data, override, filter) end
            local values = {}
            for _, field in ipairs(fields) do
                local getter = data["Get" .. field]
                if getter then values[field] = getter(data) end
            end
            -- A default zero Start is unused by most effects, not a world point.
            if not acfEffect and values.Start == Vector() then values.Start = nil end
            SendEffect(name, values, override, filter)
        end
    else
        -- Server-authoritative visuals avoid the native prediction channel's
        -- coordinate quantization and duplicate impact effects on InfMap.
        if ACF.Ballistics and ACF.Ballistics.CreatePredictedBullet then
            ACF.Ballistics.CreatePredictedBullet=function() return nil end
        end
        ACF.InfMapImpactBullets = {}
        local impactSlots, impactCursor = {}, 0
        local noVisual = {SetModel = function() end}
        local function ForgetImpact(index)
            local record = ACF.InfMapImpactBullets[index]
            if record and impactSlots[record.slot] == record then impactSlots[record.slot] = nil end
            ACF.InfMapImpactBullets[index] = nil
        end
        local function RememberImpact(index, data)
            if not data then return end
            ForgetImpact(index)
            impactCursor = impactCursor % 2048 + 1
            local old = impactSlots[impactCursor]
            if old and ACF.InfMapImpactBullets[old.index] == old then ACF.InfMapImpactBullets[old.index] = nil end
            local record = {index = index, slot = impactCursor, bullet = data, expires = RealTime() + 120}
            impactSlots[impactCursor] = record
            ACF.InfMapImpactBullets[index] = record
        end
        ACF.InfMapActiveEffects = 0
        ACF.InfMapPendingEffects, ACF.InfMapPendingCount = {}, 0
        function ACF.InfMapReleasePending(index)
            if not ACF.InfMapPendingEffects[index] then return end
            ACF.InfMapPendingEffects[index] = nil
            ACF.InfMapPendingCount = math.max(ACF.InfMapPendingCount - 1, 0)
        end
        function ACF.InfMapCleanupBullet(index, expected)
            if not expected then ACF.InfMapReleasePending(index) end
            local bullet = ACF.BulletEffect[index]
            if not bullet or (expected and bullet.Effect ~= expected) then return end
            if IsValid(bullet.Tracer) then bullet.Tracer:Finish() end
            bullet.Removed = true
            ACF.BulletEffect[index] = nil
            if bullet.InfMapManaged then
                ACF.InfMapActiveEffects = math.max(ACF.InfMapActiveEffects - 1, 0)
                bullet.InfMapManaged = false
            end
            if IsValid(bullet.Effect) then
                bullet.Effect.Kill = true
                bullet.Effect:Remove()
            end
        end
        local nextCleanup = 0
        hook.Add("Think", "ACF_InfMapEffectCleanup", function()
            local now = RealTime()
            if now < nextCleanup then return end
            nextCleanup = now + 1
            for index, record in pairs(ACF.InfMapImpactBullets) do
                if now >= record.expires then ForgetImpact(index) end
            end
            for index, pending in pairs(ACF.InfMapPendingEffects) do
                if now >= pending.expires then ACF.InfMapReleasePending(index) end
            end
            for index, bullet in pairs(ACF.BulletEffect) do
                if bullet.InfMapManaged and (not IsValid(bullet.Effect) or now >= bullet.InfMapExpireTime) then
                    ACF.InfMapCleanupBullet(index)
                end
            end
        end)
        net.Receive("ACF_InfMapBulletRemove", function()
            local index = net.ReadUInt(16)
            ForgetImpact(index)
            ACF.InfMapCleanupBullet(index)
        end)
        net.Receive("ACF_InfMapBallisticsReset", function()
            for index in pairs(ACF.BulletEffect) do ACF.InfMapCleanupBullet(index) end
            for index in pairs(ACF.InfMapPendingEffects) do ACF.InfMapReleasePending(index) end
            ACF.InfMapImpactBullets = {}
            impactSlots, impactCursor = {}, 0
        end)
        local generation = 0
        local function ReceiveEffect(name, origin, start, values, override, positionalStart)
            local offset = InfMap.unlocalize_vector(Vector(), LocalPlayer().CHUNK_OFFSET)
            if string.lower(name) == "acf_bullet_effect" then
                -- Updates modify the existing effect; never allocate a Lua effect
                -- for penetration/ricochet/end messages or orphaned updates.
                local index, hit = values.DamageType, values.Scale or 0
                local bullet = ACF.BulletEffect[index]
                if hit > 0 then
                    local record = ACF.InfMapImpactBullets[index]
                    if not bullet or not IsValid(bullet.Effect) then
                        bullet = record and record.expires > RealTime() and record.bullet or nil
                        if not bullet then
                            if hit == 1 then ACF.InfMapCleanupBullet(index) end
                            return
                        end
                    end
                    bullet.SimFlight = start * 10
                    bullet.SimPos, bullet.SimPosLast = origin - offset, origin
                    local visual = IsValid(bullet.Effect) and bullet.Effect or noVisual
                    visual.DrawEffect = (values.Attachment or 0) > 0
                    local ammo = ACF.Classes.GetSubtypeByName("ACF.Ammunition.BaseAmmo", bullet.AmmoType)
                    local method = hit == 1 and "ImpactEffect" or hit == 2 and "PenetrationEffect" or "RicochetEffect"
                    local ok, err = true
                    if ammo and ammo[method] then ok, err = pcall(ammo[method], ammo, visual, bullet) end
                    if record then record.bullet.Detonated = bullet.Detonated end
                    bullet.SimPos = origin
                    if hit == 1 then
                        ForgetImpact(index)
                        ACF.InfMapCleanupBullet(index)
                    end
                    if not ok then ErrorNoHalt(tostring(err) .. "\n") end
                    return
                end
                ACF.InfMapCleanupBullet(index)
                ForgetImpact(index)
                RememberImpact(index, values.InfMapAmmo)
                values.InfMapAmmo = nil
                if ACF.InfMapActiveEffects + ACF.InfMapPendingCount >= 256 then return end
                generation = generation % 16000000 + 1
                ACF.InfMapPendingEffects[index] = {generation = generation, expires = RealTime() + 2}
                ACF.InfMapPendingCount = ACF.InfMapPendingCount + 1
                values.Magnitude = generation
                name = "acf_infmap_bullet"
            else
                origin = origin - offset
            end
            if positionalStart then start = start - offset end
            values.Origin, values.Start = origin, start
            local data = EffectData()
            for k, v in pairs(values) do
                if data["Set" .. k] then data["Set" .. k](data, v) end
            end
            util.Effect(name, data, override, true)
        end
        net.Receive("ACF_InfMapEffect", function()
            local name = net.ReadString()
            local origin = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
            local start = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
            local values = net.ReadTable()
            local override, positionalStart = net.ReadBool(), net.ReadBool()
            ReceiveEffect(name, origin, start, values, override, positionalStart)
        end)
        net.Receive("ACF_InfMapBullet", function()
            local index, hit = net.ReadUInt(16), net.ReadUInt(2)
            local draw, override = net.ReadBool(), net.ReadBool()
            local origin = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
            local start = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
            local values = {DamageType = index, Scale = hit, Attachment = draw and 1 or 0}
            if hit == 0 then
                values.Entity = net.ReadEntity()
                if net.ReadBool() then
                    values.InfMapAmmo = {AmmoType = net.ReadString(), Caliber = net.ReadFloat(),
                        RoundMass = net.ReadFloat(), FillerMass = net.ReadFloat(), WPMass = net.ReadFloat()}
                end
            end
            ReceiveEffect("ACF_Bullet_Effect", origin, start, values, override, false)
        end)
    end
    print("[ACF InfMap] Chunk traces and bullet effects installed.")
end

hook.Add("InitPostEntity", "ACF_InfMapCompatibility", Install)
-- Supports Lua refresh after a map has initialized.
timer.Simple(0, Install)

-- Dependencies can initialize after autorun/InitPostEntity. Retry briefly, then
-- explain the missing dependency rather than silently doing nothing.
timer.Create("ACF_InfMapStartup", 1, 30, function()
    if ACF and ACF.InfMapCompatibility then
        timer.Remove("ACF_InfMapStartup")
        return
    end
    Install()
    if timer.RepsLeft("ACF_InfMapStartup") == 0 and not (ACF and ACF.InfMapCompatibility) then
        print("[ACF InfMap v37] Inactive: " .. (MissingDependencies() or "installation did not complete; check Lua errors above."))
    end
end)

if SERVER then
    concommand.Add("acf_infmap_fire_stats", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end
        local count = 0
        for _ in pairs(ACF and ACF.Ballistics and ACF.Ballistics.Bullets or {}) do count = count + 1 end
        local stats = ACF and ACF.InfMapNetworkStats or {}
        print(string.format("[ACF InfMap] Live bullets=%d compact packets=%d generic effects=%d encoded bytes=%d",
            count, stats.compact or 0, stats.generic or 0, stats.bytes or 0))
        if physenv and physenv.GetLastSimulationTime then
            print(string.format("[ACF InfMap] Last physics step: %.3f ms", physenv.GetLastSimulationTime() * 1000))
        end
    end)
    concommand.Add("acf_infmap_status", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end
        print("[ACF InfMap v37] " .. ((ACF and ACF.InfMapCompatibility)
            and "Installed for upstream ACF-3 + optional VSS extension." or ("Inactive: " .. (MissingDependencies() or "waiting for startup."))))
        if ACF and ACF.InfMapCompatibility then
            print("[ACF InfMap] Volumetric ray="..tostring(InfMap.ACFVolumetricRay==true)
                .." authoritative visuals="..tostring(ACF.InfMapAuthoritativeEffects==true)
                .." crew G-force="..tostring(ACF.InfMapCrewGForce==true)
                .." extension oxygen water="..tostring(ACF.InfMapExtensionWater==true)
                .." legacy timer override="..tostring(ACF.RACTimingFix==true))
        end
    end)
end
