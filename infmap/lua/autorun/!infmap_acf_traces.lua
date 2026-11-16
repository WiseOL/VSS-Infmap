-- Runs after !!inf_init.lua and before acf_loader.lua / scripted entity caches.
if SERVER then AddCSLuaFile() end
-- Preserve InfMap/ACF's original client HUD, camera and effect-surface traces.
if not SERVER then return end
if not InfMap or not InfMap.TraceHull or InfMap.ACFTraceV5 then return end
InfMap.ACFTraceV5 = true
local stats = { calls = 0, segments = 0, sameChunk = 0, crossChunk = 0 }
InfMap.ACFTraceStats = stats
concommand.Add("acf_infmap_trace_stats", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    print(string.format("[ACF InfMap v37] Trace calls=%d same-chunk=%d cross-chunk=%d raw-segments=%d",
        stats.calls, stats.sameChunk, stats.crossChunk, stats.segments))
end)
local rawHull, rawEntity = InfMap.TraceHull, InfMap.TraceEntity
local previousLine, previousHull, previousEntity = util.TraceLine, util.TraceHull, util.TraceEntity
local routed = setmetatable({}, {__mode = "k"})
local scopeDepth, traceWork = 0, 0
local unpackValues = unpack or table.unpack
local function Pack(...) return { n = select("#", ...), ... } end
local function Scoped(func)
    return function(...)
        if scopeDepth == 0 then traceWork = 0 end
        scopeDepth = scopeDepth + 1
        local values = Pack(pcall(func, ...))
        scopeDepth = scopeDepth - 1
        if not values[1] then error(values[2], 0) end
        return unpackValues(values, 2, values.n)
    end
end
local function GunOrRadar(data)
    if scopeDepth > 0 then return true end
    local decision = routed[data]
    if decision ~= nil then return decision end
    decision = false
    -- Resolve once per reused trace-config table, not once per entity/filter.
    -- This covers locals cached by ACF guns/radars without changing HUD or tools.
    for level = 3, 10 do
        local info = debug.getinfo(level, "S")
        if not info then break end
        local path = string.lower(info.source or ""):gsub("\\", "/")
        -- ACF AI/O computes turret HitPos in this server camera module.
        -- Its trace table is separate from HUD rangefinders and camera clipping.
        if path:find("entities/acf_controller/modules/camera.lua", 1, true) then
            decision = true
            break
        end
        if path:find("entities/acf_gun/", 1, true) or path:find("entities/acf_radar/", 1, true) then
            decision = true
            break
        end
        if path:find("entities/", 1, true) or path:find("starfall", 1, true) then break end
    end
    routed[data] = decision
    return decision
end
-- Split at every crossed chunk plane. No time-step changes: fractions are
-- remapped to the original ray so ACF's fuze/penetration logic still works.
local sameChunkCuts = {0, 1}
local zeroHull = Vector()
local function TraceInner(data, raw, extra, line)
    stats.calls = stats.calls + 1
    local start, finish = data.start, data.endpos
    local direction = finish - start
    -- Reject non-finite vectors before calculating any loop bounds.
    for axis = 1, 3 do
        if start[axis] ~= start[axis] or finish[axis] ~= finish[axis]
            or math.abs(start[axis]) == math.huge or math.abs(finish[axis]) == math.huge then
            error("[ACF InfMap] Invalid trace coordinates", 0)
        end
    end
    local width = InfMap.chunk_size * 2
    local old = data.filter
    local excluded
    if istable(old) and not IsEntity(old) then
        excluded = {}
        for _, value in ipairs(old) do excluded[value] = true end
    end
    local cuts = sameChunkCuts
    local _, startChunk = InfMap.localize_vector(start)
    local _, endChunk = InfMap.localize_vector(finish)
    if startChunk ~= endChunk then
    cuts = {0, 1}
    stats.crossChunk = stats.crossChunk + 1
    for axis = 1, 3 do
        local a, b = start[axis], finish[axis]
        if a ~= b then
            local low, high = math.min(a, b), math.max(a, b)
            local first = math.floor((low + InfMap.chunk_size) / width) + 1
            local last = math.ceil((high + InfMap.chunk_size) / width) - 1
            if last - first + 1 + #cuts > 258 then
                error("[ACF InfMap] Trace crosses too many chunks (limit 256 planes)", 0)
            end
            for n = first, last do
                cuts[#cuts + 1] = (n * width - InfMap.chunk_size - a) / direction[axis]
            end
        end
    end
    table.sort(cuts)
    else
        stats.sameChunk = stats.sameChunk + 1
    end
    local result
    local initiallySolid, solidExit, exitPos
    for i = 1, #cuts - 1 do
        local from, to = cuts[i], cuts[i + 1]
        if to > from then
            local chunk = startChunk
            if startChunk ~= endChunk then
                local ignored
                ignored, chunk = InfMap.localize_vector(start + direction * ((from + to) * 0.5))
            end
            local offset = InfMap.unlocalize_vector(Vector(), chunk)
            local segment = {}
            for k, v in pairs(data) do segment[k] = v end
            if line then segment.mins, segment.maxs = zeroHull, zeroHull end
            segment.output = nil
            segment.start = start + direction * from - offset
            segment.endpos = start + direction * to - offset
            segment.whitelist = nil
            segment.filter = function(ent)
                if ent.CHUNK_OFFSET ~= chunk then return false end
                local target = ent
                if ent:GetClass() == "infmap_clone" and ent.REFERENCE_DATA then
                    target = ent.REFERENCE_DATA.parent or ent.REFERENCE_DATA[1] or ent
                elseif ent:GetClass() == "infmap_clone" and ent.GetReferenceParent then
                    local parent = ent:GetReferenceParent()
                    if IsValid(parent) then target = parent end
                end
                if isfunction(old) then return old(target) end
                local listed = false
                if IsEntity(old) then listed = target == old or ent == old
                elseif excluded then
                    listed = excluded[target] or excluded[ent] or false
                end
                if data.whitelist then return listed end
                return not listed
            end
            if scopeDepth > 0 then traceWork = traceWork + 1 end
            if scopeDepth > 0 and traceWork > 4096 then
                error("[ACF InfMap] Repeated trace budget exceeded; possible ACF filter retry loop", 0)
            end
            stats.segments = stats.segments + 1
            local began = InfMap.ACFFireProfiling and SysTime()
            result = raw(segment, extra)
            if began then stats.rawSeconds = (stats.rawSeconds or 0) + SysTime() - began end
            if from == 0 then initiallySolid = result.StartSolid end
            local stillSolid = initiallySolid and solidExit == nil and result.AllSolid
            result.HitPos = result.HitPos + offset
            result.StartPos = from == 0 and (result.StartPos + offset) or start
            result.Fraction = from + (to - from) * result.Fraction
            if result.FractionLeftSolid and result.FractionLeftSolid > 0 then
                result.FractionLeftSolid = from + (to - from) * result.FractionLeftSolid
            end
            if initiallySolid and not stillSolid then
                if solidExit == nil then
                    solidExit = result.StartSolid and (result.FractionLeftSolid or from) or from
                    exitPos = start + direction * solidExit
                end
                result.StartSolid = true
                result.FractionLeftSolid = solidExit
                result.StartPos = exitPos
            end
            local ent = result.Entity
            if IsValid(ent) then
                if ent:GetClass() == "infmap_clone" and ent.REFERENCE_DATA then
                    result.Entity = ent.REFERENCE_DATA.parent or ent.REFERENCE_DATA[1] or ent
                elseif ent:GetClass() == "infmap_clone" and ent.GetReferenceParent then
                    local parent = ent:GetReferenceParent()
                    if IsValid(parent) then result.Entity = parent end
                elseif InfMap.disable_pickup[ent:GetClass()] then
                    result.Entity = game.GetWorld()
                    result.HitWorld = true
                    result.HitNonWorld = false
                end
            end
            if stillSolid then
                -- A solid may continue into the next chunk. Do not report that
                -- chunk's boundary as a penetration exit.
                result.StartSolid = true
                result.AllSolid = true
                result.FractionLeftSolid = 1
                result.Fraction = 0
                result.StartPos, result.HitPos = start, start
            elseif result.Hit then
                break
            end
        end
    end
    -- Preserve the output-table contract used by ACF.trace.
    if data.output then
        for k in pairs(data.output) do data.output[k] = nil end
        for k, v in pairs(result) do data.output[k] = v end
        return data.output
    end
    return result
end
local function Trace(...)
    if not InfMap.ACFFireProfiling then return TraceInner(...) end
    local began = SysTime()
    local result = TraceInner(...)
    stats.seconds = (stats.seconds or 0) + SysTime() - began
    return result
end
-- Installed before ACF caches its trace functions. Only gun/radar calls use
-- the splitter; all other callers delegate to the previous InfMap functions.
util.TraceHull = function(data, ...)
    if not GunOrRadar(data) then return previousHull(data, ...) end
    return Trace(data, rawHull)
end
util.TraceLine = function(data)
    if not GunOrRadar(data) then return previousLine(data) end
    return Trace(data, rawHull, nil, true)
end
util.TraceEntity = function(data, ent)
    if not GunOrRadar(data) then return previousEntity(data, ent) end
    return Trace(data, rawEntity, ent)
end
InfMap.ACFScoped = Scoped

-- Current ACF gathers volumetric armor through a broad-phase entity ray.
-- Use the same chunk frames as the physics trace, only inside ACF scopes.
local previousAlongRay=ents and ents.FindAlongRay
if previousAlongRay then
    InfMap.ACFVolumetricRay=true
    ents.FindAlongRay=function(start,finish,mins,maxs)
        if scopeDepth==0 then return previousAlongRay(start,finish,mins,maxs) end
        local width=InfMap.chunk_size*2
        local direction=finish-start
        local cuts={0,1}
        for axis=1,3 do
            local a,b=start[axis],finish[axis]
            if a~=a or b~=b or math.abs(a)==math.huge or math.abs(b)==math.huge then error("[ACF InfMap] Invalid armor ray",0) end
            if a~=b then
                local first=math.floor((math.min(a,b)+InfMap.chunk_size)/width)+1
                local last=math.ceil((math.max(a,b)+InfMap.chunk_size)/width)-1
                if last-first+1+#cuts>258 then error("[ACF InfMap] Armor ray crosses too many chunks",0) end
                for plane=first,last do cuts[#cuts+1]=(plane*width-InfMap.chunk_size-a)/direction[axis] end
            end
        end
        table.sort(cuts)
        local found,seen={},{}
        for i=1,#cuts-1 do
            local from,to=cuts[i],cuts[i+1]
            if to>from then
                local _,chunk=InfMap.localize_vector(start+direction*((from+to)*0.5))
                local offset=chunk*width
                traceWork=traceWork+1
                if traceWork>4096 then error("[ACF InfMap] Armor ray budget exceeded",0) end
                for _,ent in ipairs(previousAlongRay(start+direction*from-offset,start+direction*to-offset,mins,maxs)) do
                    if ent.CHUNK_OFFSET==chunk then
                        local target=ent
                        if ent:GetClass()=="infmap_clone" then
                            if ent.REFERENCE_DATA then target=ent.REFERENCE_DATA.parent or ent.REFERENCE_DATA[1] or ent
                            elseif ent.GetReferenceParent then
                                local parent=ent:GetReferenceParent()
                                if IsValid(parent) then target=parent end
                            end
                        end
                        if not seen[target] then seen[target]=true found[#found+1]=target end
                    end
                end
            end
        end
        return found
    end
end

