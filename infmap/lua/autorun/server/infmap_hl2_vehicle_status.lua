-- Read-only diagnostics for native vehicle contacts; no wheel-force workaround.
concommand.Add("infmap_hl2_vehicle_status", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    if not InfMap then return end
    local function Read(object, method, ...)
        if not object or not object[method] then return end
        local ok, a, b, c = pcall(object[method], object, ...)
        if ok then return a, b, c end
    end
    local function Vec(v) if v then return {x=v.x, y=v.y, z=v.z} end end
    local records = {}
    for _, vehicle in ipairs(ents.FindByClass("prop_vehicle_*")) do
        if #records >= 16 then break end
        local count = Read(vehicle, "GetWheelCount") or 0
        local record = {class=vehicle:GetClass(), index=vehicle:EntIndex(), chunk=Vec(vehicle.CHUNK_OFFSET),
            position=Vec(vehicle:GetPos()), nativeWater=Read(vehicle, "WaterLevel"), wheels={}}
        records[#records + 1] = record
        for i=0, math.min(count, 16)-1 do
            local wheel = Read(vehicle, "GetWheel", i)
            local contact, surface, hit = Read(vehicle, "GetWheelContactPoint", i)
            local entry = {index=i, contact=Vec(contact), surface=surface, nativeContact=hit}
            record.wheels[#record.wheels + 1] = entry
            if IsValid(wheel) then
                entry.collisions = Read(wheel, "IsCollisionEnabled")
                entry.gameFlags = Read(wheel, "GetGameFlags")
                local pos = Read(wheel, "InfMap_GetPos") or Read(wheel, "GetPos")
                entry.nativePosition=Vec(pos)
                if pos and InfMap.TraceLine then
                    local tr = InfMap.TraceLine({start=pos + Vector(0,0,64), endpos=pos - Vector(0,0,128),
                        mask=MASK_SOLID, filter=vehicle})
                    entry.traceHit=tr.Hit
                    entry.traceEntity=IsValid(tr.Entity) and tr.Entity:GetClass() or "world/none"
                    entry.tracePosition=Vec(tr.HitPos)
                end
            end
        end
    end
    local result = util.TableToJSON(records, true)
    file.CreateDir("infmap") file.Write("infmap/hl2_vehicle_latest.json", result or "[]")
    local text = "[InfMap HL2] Saved " .. #records .. " vehicles to data/infmap/hl2_vehicle_latest.json\n" .. (result or "[]")
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, text) else print(text) end
end)
