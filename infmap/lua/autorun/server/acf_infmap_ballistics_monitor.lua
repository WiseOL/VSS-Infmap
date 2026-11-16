-- Opt-in overload reset; monitoring never changes simulation cadence.
local cvMS = CreateConVar("acf_infmap_ballistics_max_ms", "0", FCVAR_ARCHIVE,
    "Reset after sustained average ACF creation/iteration ms per server tick; 0 disables.", 0, 1000)
local cvCount = CreateConVar("acf_infmap_ballistics_max_count", "0", FCVAR_ARCHIVE,
    "Reset after sustained active bullet count; 0 disables.", 0, 100000)
local cvHold = CreateConVar("acf_infmap_ballistics_hold", "2", FCVAR_ARCHIVE, "Overload duration before reset.", 1, 60)
local cvCooldown = CreateConVar("acf_infmap_ballistics_cooldown", "10", FCVAR_ARCHIVE, "Minimum seconds between automatic resets.", 1, 300)
local watchers = setmetatable({}, {__mode = "k"})
local monitor, lastReset = nil, -math.huge
local pack = function(...) return {n = select("#", ...), ...} end
local unpackValues = unpack or table.unpack
local function Allowed(ply) return not IsValid(ply) or ply:IsSuperAdmin() end
local function Say(ply, text)
    text = "[ACF ballistics] " .. text
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, text .. "\n") else print(text) end
end
local function Count()
    local n = 0
    for _ in pairs(monitor.ballistics.Bullets) do n = n + 1 end
    return n
end
local function Reset(reason)
    if not monitor or ACF.InfMapResettingBallistics then return end
    if monitor.depth > 0 then
        if not monitor.resetQueued then
            monitor.resetQueued = true
            timer.Simple(0, function() monitor.resetQueued = nil Reset(reason) end)
        end
        return "Reset queued until ballistic processing finishes."
    end
    local b = monitor.ballistics
    local snapshot = {}
    for index, bullet in pairs(b.Bullets) do snapshot[#snapshot + 1] = {index, bullet} end
    -- Keep the same table: ACF caches its reference. Block callback-created
    -- bullets during cleanup and send one client reset instead of N messages.
    ACF.InfMapResettingBallistics = true
    local failures = 0
    for _, entry in ipairs(snapshot) do
        local index, bullet = entry[1], entry[2]
        if type(bullet) == "table" then
            local ok, err = pcall(b.RemoveBullet, bullet)
            if not ok then
                failures = failures + 1
                if failures <= 3 then print("[ACF ballistics] Cleanup error: " .. tostring(err)) end
            end
            bullet.Removed = true
        end
        if b.Bullets[index] == bullet then b.Bullets[index] = nil end
        if b.UnusedIndexes then b.UnusedIndexes[index] = true end
        local owned=b.PredictedBullets and type(bullet)=="table" and b.PredictedBullets[bullet.Owner]
        if owned then
            owned[index]=nil
            if not next(owned) then b.PredictedBullets[bullet.Owner]=nil end
        end
    end
    ACF.InfMapResettingBallistics = nil
    if not next(b.Bullets) then hook.Remove("ACF_OnTick", "ACF Iterate Bullets") end
    net.Start("ACF_InfMapBallisticsReset") net.Broadcast()
    lastReset = SysTime()
    monitor.overloadedSince = nil
    monitor.elapsed, monitor.calls = 0, 0
    monitor.started, monitor.tick = lastReset, engine.TickCount()
    monitor.lastCount, monitor.lastMS = Count(), 0
    monitor.resets = monitor.resets + 1
    local message = string.format("Reset %d bullets (%s); cleanup callback errors=%d.", #snapshot, reason, failures)
    print("[ACF ballistics] " .. message)
    return message
end
local function Line()
    local interval = engine.TickInterval() * 1000
    return string.format("Active=%d | ACF %.3f ms/tick (%.1f%% of %.2f ms budget) | observed %.1f ticks/s | resets=%d | limits %.2f ms / %d bullets, hold %.1fs, cooldown %.1fs",
        Count(), monitor.lastMS or 0, (monitor.lastMS or 0) / interval * 100,
        interval, monitor.rate or 0, monitor.resets, cvMS:GetFloat(), cvCount:GetInt(), cvHold:GetFloat(), cvCooldown:GetFloat())
end
local function Install()
    if monitor then return true end
    local b = ACF and ACF.Ballistics
    if not InfMap or not ACF or not ACF.InfMapCompatibility or not b or not b.Bullets
        or not b.CreateBullet or not b.IterateBullets or not b.RemoveBullet then return end
    util.AddNetworkString("ACF_InfMapBallisticsReset")
    monitor = {ballistics=b, elapsed=0, calls=0, depth=0, started=SysTime(), tick=engine.TickCount(), resets=0}
    local metrics = {seconds=0, calls=0, created=0}
    ACF.InfMapBallisticsMetrics = metrics
    local function Timed(original, isCreate)
        return function(...)
            if isCreate and ACF.InfMapResettingBallistics then return end
            local outer = monitor.depth == 0
            local start = outer and SysTime()
            monitor.depth = monitor.depth + 1
            local result = pack(pcall(original, ...))
            monitor.depth = monitor.depth - 1
            if outer then
                local elapsed = SysTime() - start
                monitor.elapsed = monitor.elapsed + elapsed
                metrics.seconds = metrics.seconds + elapsed
                metrics.calls = metrics.calls + 1
                monitor.calls = monitor.calls + 1
            end
            if isCreate and result[1] and result[2] then metrics.created = metrics.created + 1 end
            if not result[1] then error(result[2], 0) end
            return unpackValues(result, 2, result.n)
        end
    end
    local original = b.IterateBullets
    b.IterateBullets = Timed(original, false)
    b.CreateBullet = Timed(b.CreateBullet, true)
    local predicted=b.IteratePredictedBullets
    if predicted then b.IteratePredictedBullets=Timed(predicted,false) end
    local hooks = hook.GetTable()
    if hooks.ACF_OnTick and hooks.ACF_OnTick["ACF Iterate Bullets"] == original then
        hook.Add("ACF_OnTick", "ACF Iterate Bullets", b.IterateBullets)
    end
    if predicted and hooks.PlayerTick and hooks.PlayerTick["ACF Iterate Predicted Bullets"]==predicted then
        hook.Add("PlayerTick","ACF Iterate Predicted Bullets",b.IteratePredictedBullets)
    end
    timer.Create("ACF_InfMapBallisticsMonitor", 0.25, 0, function()
        local now = SysTime()
        local duration = now - monitor.started
        if duration < 1 then return end
        local ticks = engine.TickCount() - monitor.tick
        monitor.lastMS = monitor.elapsed * 1000 / math.max(ticks, 1)
        monitor.rate = ticks / duration
        monitor.lastCount = Count()
        local ms, count = cvMS:GetFloat(), cvCount:GetInt()
        local high = (ms > 0 and monitor.lastMS > ms) or (count > 0 and monitor.lastCount > count)
        if high then monitor.overloadedSince = monitor.overloadedSince or monitor.started
        else monitor.overloadedSince = nil end
        if high and now - monitor.overloadedSince >= cvHold:GetFloat() and now - lastReset >= cvCooldown:GetFloat() then
            Reset(string.format("automatic: %.3f ms/tick, %d live bullets", monitor.lastMS, monitor.lastCount))
        end
        for ply, expires in pairs(watchers) do
            if not IsValid(ply) or not ply:IsSuperAdmin() or now >= expires then watchers[ply] = nil
            else Say(ply, Line()) end
        end
        monitor.elapsed, monitor.calls = 0, 0
        monitor.started, monitor.tick = now, engine.TickCount()
    end)
    print("[ACF ballistics] Monitor installed; automatic resets require nonzero thresholds.")
    return true
end
concommand.Add("acf_infmap_ballistics", function(ply, _, args)
    if not Allowed(ply) then return end
    if not monitor then Say(ply, "Unavailable: InfMap/ACF compatibility has not initialized.") return end
    local action = string.lower(args[1] or "status")
    if action == "reset" then Say(ply, Reset("manual") or "Reset already running.")
    elseif action == "limits" then
        local ms, count = tonumber(args[2]), tonumber(args[3])
        if not ms or not count or ms ~= ms or count ~= count or ms < 0 or ms > 1000 or count < 0 or count > 100000 then
            Say(ply, "Usage: acf_infmap_ballistics limits <ms-per-tick> <bullet-count>; 0 disables that threshold.") return
        end
        local hold, cooldown = cvHold:GetFloat(), cvCooldown:GetFloat()
        if args[4] then hold = tonumber(args[4]) end
        if args[5] then cooldown = tonumber(args[5]) end
        if not hold or not cooldown or hold ~= hold or cooldown ~= cooldown or hold < 1 or hold > 60 or cooldown < 1 or cooldown > 300 then
            Say(ply, "Hold must be 1-60 seconds; cooldown must be 1-300 seconds.") return
        end
        cvHold:SetFloat(hold) cvCooldown:SetFloat(cooldown)
        cvMS:SetFloat(ms) cvCount:SetInt(math.floor(count)) monitor.overloadedSince = nil
        Say(ply, Line())
    elseif action == "off" then
        cvMS:SetFloat(0) cvCount:SetInt(0) monitor.overloadedSince = nil
        Say(ply, "Automatic resets disabled; monitoring remains active.")
    elseif action == "watch" then
        if not IsValid(ply) then Say(ply, "Use status from server console; watch streams to a player's console.") return end
        watchers[ply] = SysTime() + math.Clamp(tonumber(args[2]) or 30, 1, 60)
        Say(ply, Line())
    elseif action == "stop" then watchers[ply] = nil
    elseif action == "list" then
        local limit = math.Clamp(math.floor(tonumber(args[2]) or 20), 1, 100)
        Say(ply, Line())
        for index, bullet in pairs(monitor.ballistics.Bullets) do
            if limit <= 0 then break end
            local owner = type(bullet) == "table" and bullet.Owner
            Say(ply, string.format("#%s ammo=%s owner=%s", tostring(index),
                tostring(type(bullet) == "table" and (bullet.Type or bullet.AmmoType) or "invalid"),
                IsValid(owner) and owner:IsPlayer() and owner:Nick() or "unknown"))
            limit = limit - 1
        end
    elseif action == "status" then Say(ply, Line())
    else Say(ply, "Commands: status | watch [seconds] | stop | list [limit] | limits <ms> <count> | off | reset") end
end)
hook.Add("InitPostEntity", "ACF_InfMapBallisticsMonitor", Install)
hook.Add("ACF_OnLoadAddon", "ACF_InfMapBallisticsMonitor", Install)
timer.Simple(0, Install)
timer.Create("ACF_InfMapBallisticsMonitorStartup", 1, 30, function()
    if Install() then timer.Remove("ACF_InfMapBallisticsMonitorStartup") end
end)
