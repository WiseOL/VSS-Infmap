-- Give the extension's oxygen sampler synthetic-water contents without
-- changing util.PointContents for unrelated addons or replacing crew logic.
local patched=setmetatable({}, {__mode="k"})
local function Install()
    if not InfMap or not InfMap.localize_vector or not getfenv or not setfenv then return end
    local stored=scripted_ents.GetStored("acf_crew")
    local method=stored and stored.t and stored.t.UpdateLowFreq
    if not method or patched[method] then return end
    local info=debug.getinfo(method,"S")
    local path=string.lower(info.source or ""):gsub("\\","/")
    if not path:find("acf/vss/acf_crew_sv.lua",1,true) then return end
    local previous=getfenv(method)
    local utilities=previous.util or util
    local contents=utilities.PointContents
    local proxy=setmetatable({}, {__index=utilities})
    proxy.PointContents=function(pos)
        local native=InfMap.localize_vector(pos)
        local value=contents(native)
        if type(InfMap.water_height)=="number" and pos.z<InfMap.water_height then
            return bit.bor(value,CONTENTS_WATER)
        end
        return value
    end
    setfenv(method,setmetatable({util=proxy},{__index=previous}))
    patched[method]=true
    if ACF then ACF.InfMapExtensionWater=true end
    print("[ACF InfMap] VSS extension crew oxygen water sampling installed.")
end
hook.Add("InitPostEntity","ACF_InfMapExtensionWater",Install)
hook.Add("ACF_OnLoadAddon","ACF_InfMapExtensionWater",Install)
timer.Simple(0,Install)
timer.Create("ACF_InfMapExtensionWaterStartup",1,30,Install)
