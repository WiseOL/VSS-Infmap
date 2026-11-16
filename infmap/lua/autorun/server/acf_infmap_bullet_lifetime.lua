-- InfMap ballistic lifetime/range guard. Traces are synchronous queries, not
-- persistent objects: stop flight before tracing, then remove the owning bullet.
local maxAge = CreateConVar("acf_infmap_bullet_max_age", "30", FCVAR_ARCHIVE,
    "Maximum real seconds per InfMap ACF bullet; 0 disables age expiry.", 0, 3600)
local maxRange = CreateConVar("acf_infmap_bullet_max_range", "1000000", FCVAR_ARCHIVE,
    "Maximum Source-unit radius from bullet launch; 0 disables range expiry.", 0, 100000000)
local installed
local state = setmetatable({}, {__mode="k"})
local stats = {age=0, range=0, invalid=0, oversized=0, errors=0}
local removing = false
local predictedKeys = {"NextPos", "TraceTo"}
local function Finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function ValidPos(p) return p and Finite(p.x) and Finite(p.y) and Finite(p.z) end
local function Track(bullet)
    local data = state[bullet]
    if not data then
        local p = bullet.Pos
        data = {born=SysTime()}
        if ValidPos(p) then data.x, data.y, data.z = p.x, p.y, p.z end
        state[bullet] = data
    end
    return data
end
local function Reason(bullet, now, predicted)
    local data = Track(bullet)
    if not ValidPos(bullet.Pos) or not data.x then return "invalid" end
    local age, range = maxAge:GetFloat(), maxRange:GetFloat()
    if age>0 and now-data.born>=age then return "age" end
    local function Check(p)
        if not ValidPos(p) then return "invalid" end
        local dx,dy,dz = p.x-data.x,p.y-data.y,p.z-data.z
        if range>0 and dx*dx+dy*dy+dz*dz>=range*range then return "range" end
    end
    local reason = Check(bullet.Pos)
    if reason then return reason end
    if predicted then
        for _, key in ipairs(predictedKeys) do
            local p = bullet[key]
            if p then
                local why = Check(p)
                if why then return why end
                local start = bullet.Pos
                local span = math.abs(p.x-start.x)+math.abs(p.y-start.y)+math.abs(p.z-start.z)
                if span > (InfMap.chunk_size or 10000)*2*240 then return "oversized" end
            end
        end
    end
end
local function Install()
    if installed then return true end
    local b = ACF and ACF.Ballistics
    if not InfMap or not ACF or not ACF.InfMapCompatibility or not b or not b.Bullets
        or not b.RemoveBullet or not b.CalcBulletFlight or not b.DoBulletsFlight or not b.CreateBullet then return end
    local function Cull(bullet, reason)
        if bullet.Removed or b.Bullets[bullet.Index]~=bullet then return end
        -- Keep the original removal path, including the compatibility layer's
        -- reliable client cleanup notification. Never detonate on expiry.
        local previous = removing
        removing = true
        local ok, err = pcall(b.RemoveBullet, bullet)
        removing = previous
        if not ok then
            stats.errors = stats.errors+1
            if stats.errors<=3 then print("[ACF InfMap expiry] Removal callback error: "..tostring(err)) end
        end
        if b.Bullets[bullet.Index]==bullet then
            b.Bullets[bullet.Index]=nil
            if b.UnusedIndexes then b.UnusedIndexes[bullet.Index]=true end
        end
        local owned=b.PredictedBullets and b.PredictedBullets[bullet.Owner]
        if owned then
            owned[bullet.Index]=nil
            if not next(owned) then b.PredictedBullets[bullet.Owner]=nil end
        end
        bullet.Removed = true
        state[bullet] = nil
        stats[reason] = stats[reason]+1
        if not next(b.Bullets) then hook.Remove("ACF_OnTick", "ACF Iterate Bullets") end
    end
    local create, calc, flight = b.CreateBullet, b.CalcBulletFlight, b.DoBulletsFlight
    b.CreateBullet = function(...)
        if removing then return end -- expiry callbacks must not spawn replacements
        local bullet = create(...)
        if type(bullet)=="table" and not bullet.Removed then Track(bullet) end
        return bullet
    end
    local function Guard(original, predicted)
        return function(bullet, ...)
            if type(bullet)~="table" then return original(bullet, ...) end
            if bullet.Removed then return end
            local reason = Reason(bullet, SysTime(), predicted)
            if reason then return Cull(bullet, reason) end
            return original(bullet, ...)
        end
    end
    b.CalcBulletFlight = Guard(calc, false)
    b.DoBulletsFlight = Guard(flight, true)
    -- Also catches HandlesOwnIteration/custom rounds that stop calling ACF's
    -- flight path. Bounded removal batches avoid one large cleanup spike.
    timer.Create("ACF_InfMapBulletExpiry", 0.25, 0, function()
        local now, removed = SysTime(), 0
        for _, bullet in pairs(b.Bullets) do
            if type(bullet)=="table" and not bullet.Removed then
                local reason = Reason(bullet, now, false)
                if reason then
                    Cull(bullet, reason)
                    removed = removed+1
                    if removed>=128 then break end
                end
            end
        end
    end)
    concommand.Add("acf_infmap_bullet_cleanup_status", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local count=0 for _ in pairs(b.Bullets) do count=count+1 end
        local message=string.format("[ACF InfMap expiry] Active=%d age=%.1fs range=%.0f units | culled age=%d range=%d invalid=%d oversized=%d callbackErrors=%d",
            count,maxAge:GetFloat(),maxRange:GetFloat(),stats.age,stats.range,stats.invalid,stats.oversized,stats.errors)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE,message.."\n") else print(message) end
    end)
    installed=true
    print("[ACF InfMap] Bullet age/range guards installed.")
    return true
end
hook.Add("InitPostEntity", "ACF_InfMapBulletExpiry", Install)
hook.Add("ACF_OnLoadAddon", "ACF_InfMapBulletExpiry", Install)
timer.Simple(0, Install)
timer.Create("ACF_InfMapBulletExpiryStartup",1,30,function()
    if Install() then timer.Remove("ACF_InfMapBulletExpiryStartup") end
end)
