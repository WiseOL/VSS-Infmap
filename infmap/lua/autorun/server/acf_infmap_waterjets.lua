-- Only bridge water detection for ACF jets. Do not detour PointContents or
-- change thrust, gearing, steering, sound, scheduling or naval restrictions.
local installed = {}
local function RefreshWater(self)
    if not InfMap or type(InfMap.water_height) ~= "number" then return end
    local pos = self:GetPos() -- InfMap's global coordinates, including Z chunks.
    local nativePos = self.InfMap_GetPos and self:InfMap_GetPos() or pos
    self:GetTable().InWater = pos.z < InfMap.water_height
        or bit.band(util.PointContents(nativePos), CONTENTS_WATER) == CONTENTS_WATER
end
local function Install()
    if not InfMap or not InfMap.localize_vector or not ACF then return end
    for _, class in ipairs({"acf_waterjet", "acf_naval_waterjet"}) do
        local stored = scripted_ents.GetStored(class)
        local methods = stored and stored.t
        if methods and not installed[methods] and methods.Think and methods.Calc and methods.Act then
            local think, calc, act = methods.Think, methods.Calc, methods.Act
            methods.Think = function(self, ...)
                local result = think(self, ...)
                if IsValid(self) then RefreshWater(self) end
                return result
            end
            methods.Calc = function(self, ...)
                RefreshWater(self)
                return calc(self, ...)
            end
            methods.Act = function(self, ...)
                RefreshWater(self)
                return act(self, ...)
            end
            installed[methods] = true
            print("[ACF InfMap] Water detection installed for " .. class .. ".")
        end
    end
end
hook.Add("InitPostEntity", "ACF_InfMapWaterjets", Install)
hook.Add("ACF_OnLoadAddon", "ACF_InfMapWaterjets", Install)
timer.Simple(0, Install)
timer.Create("ACF_InfMapWaterjetsStartup", 1, 30, Install)
