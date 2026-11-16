-- TFE/SafeNet camera aim uses client render coordinates. ACF on the server
-- requires global coordinates. Convert only the known absolute Aim payload;
-- never change traces, generic vector networking, or already-relative scripts.
if SERVER then AddCSLuaFile() return end
if not InfMap or not InfMap.unlocalize_vector then return end

hook.Add("StarfallPostInstanceCompile", "ACF_InfMapCameraAim", function(instance)
    local source = instance.source and instance.source[instance.mainfile]
    if type(source) ~= "string" then return end
    if not source:find("AimOutput", 1, true)
        or not source:find("input.screenToVector", 1, true)
        or not source:match('net%.start%s*%(%s*["\']Aim["\']%s*%)')
        or not source:match("net%.writeVector%s*%(%s*localDidhit%.HitPos%s*%)") then return end

    local env = instance.env
    local requireOriginal = env.require
    local vectors = instance.Types.Vector
    local wrapped = setmetatable({}, { __mode = "k" })
    env.require = function(path, ...)
        local library = requireOriginal(path, ...)
        if path ~= "SafeNet" or type(library) ~= "table" or wrapped[library] then return library end
        if type(library.start) ~= "function" or type(library.writeVector) ~= "function" then return library end
        wrapped[library] = true
        local startOriginal, writeOriginal = library.start, library.writeVector
        local aim = false
        library.start = function(name, ...)
            aim = name == "Aim"
            return startOriginal(name, ...)
        end
        library.writeVector = function(value, ...)
            if aim then
                -- Read the viewer's chunk at serialization time: queued packets
                -- must keep the frame in which their HitPos was calculated.
                local viewer = LocalPlayer()
                if IsValid(viewer) and viewer.CHUNK_OFFSET then
                    value = vectors.Wrap(InfMap.unlocalize_vector(vectors.Unwrap(value), viewer.CHUNK_OFFSET))
                end
            end
            return writeOriginal(value, ...)
        end
        print("[ACF InfMap] TFE camera aim coordinate bridge installed.")
        return library
    end
end)
