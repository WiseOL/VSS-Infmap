-- E2 holoPos reaches WireLib.setPos, whose normal Source-world clamp runs
-- before InfMap's SetPos conversion. Keep the exception hologram-only.
local installed
local function Finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
local function Install()
    if installed then return true end
    if not InfMap or not InfMap.localize_vector or not InfMap.prop_update_chunk
        or not WireLib or not WireLib.setPos then return end
    local original = WireLib.setPos
    WireLib.setPos = function(ent, pos, ...)
        if not IsValid(ent) or ent:GetClass() ~= "gmod_wire_hologram" then
            return original(ent, pos, ...)
        end
        if not Finite(pos.x) or not Finite(pos.y) or not Finite(pos.z) then return end
        local parent = ent:GetParent()
        if IsValid(parent) and ent.InfMap_SetPos then
            -- A parented child must share the physical root's native coordinate
            -- frame, even when its global position lies across a chunk boundary.
            local root = parent
            for depth = 1, 64 do
                local nextParent = root:GetParent()
                if not IsValid(nextParent) then break end
                root = nextParent
                if depth == 64 then return end -- malformed/cyclic parent graph
            end
            local chunk = root.CHUNK_OFFSET
            if chunk then
                InfMap.prop_update_chunk(ent, chunk)
                local native = pos - InfMap.unlocalize_vector(Vector(), chunk)
                -- Retain Source bounds in the native frame; only the global
                -- pre-clamp is bypassed. Huge parent-relative offsets still
                -- cannot be represented by the engine.
                if WireLib.clampPos then native = WireLib.clampPos(native) end
                return ent:InfMap_SetPos(native)
            end
        end
        -- Unparented holograms use the regular InfMap SetPos path, with no
        -- pre-clamp. Wire's existing E2 ownership/index checks still run first.
        return ent:SetPos(pos)
    end
    installed = true
    print("[Wire InfMap] E2 hologram global positioning installed.")
    return true
end
hook.Add("InitPostEntity", "InfMapWireHolograms", Install)
timer.Simple(0, Install)
timer.Create("InfMapWireHologramsStartup", 1, 30, function()
    if Install() then timer.Remove("InfMapWireHologramsStartup") end
end)
