-- Compatibility for the verified Workshop/GitHub Tank Track Tool revision.
local prefix="infmap/compat/tanktracktool/"
if SERVER then
    AddCSLuaFile()
    for _,name in ipairs({"bridge.lua","patches.lua"}) do AddCSLuaFile(prefix..name) end
    return
end
local function Install()
    if not InfMap or not InfMap.PropNativePose or not tanktracktool or not tanktracktool.render then return end
    if InfMap.TankTracksV36 then return end
    local expected={
        ["tanktracktool/client/render/mode.lua"]="917322356",
        ["entities/sent_tanktracks_legacy/cl_init.lua"]="1959755780",
        ["entities/sent_tanktracks_auto/cl_init.lua"]="3975457005",
    }
    for path,crc in pairs(expected) do
        local source=file.Read(path,"LUA")
        if not source or util.CRC(string.gsub(source,"\r\n","\n"))~=crc then
            ErrorNoHalt("[InfMap tracks] Unsupported Tank Track Tool source: "..path.."; adapter skipped.\n")
            timer.Remove("InfMapTankTracksStartup")
            return
        end
    end
    local legacy=scripted_ents.GetStored("sent_tanktracks_legacy")
    local auto=scripted_ents.GetStored("sent_tanktracks_auto")
    if not legacy or not auto then return end
    include(prefix.."bridge.lua")
    include(prefix.."patches.lua")
    local function LoadAdapter(name,path)
        local source=file.Read(path,"LUA"):gsub("\r\n","\n")
        local compiled=CompileString(InfMap.BuildTrackAdapter(name,source),"@"..path,false)
        if type(compiled)~="function" then error(compiled,0) end
        compiled()
    end
    local previousENT=ENT
    local ok,err=xpcall(function()
        LoadAdapter("mode","tanktracktool/client/render/mode.lua")
        ENT=legacy.t ENT.tanktracktool_linkData={} LoadAdapter("legacy","entities/sent_tanktracks_legacy/cl_init.lua")
        ENT=auto.t LoadAdapter("auto","entities/sent_tanktracks_auto/cl_init.lua")
    end,debug.traceback)
    ENT=previousENT
    if not ok then ErrorNoHalt("[InfMap tracks] Adapter load failed: "..tostring(err).."\n") return end
    for _,class in ipairs({"sent_tanktracks_auto","sent_tanktracks_legacy"}) do
        for _,ent in ipairs(ents.FindByClass(class)) do ent.tanktracktool_reset=true end
    end
    InfMap.TankTracksV36=true
    timer.Remove("InfMapTankTracksStartup")
    print("[InfMap tracks v36] Workshop/GitHub automatic and legacy rendering installed.")
end
hook.Add("InitPostEntity","InfMapTankTracks",Install)
timer.Create("InfMapTankTracksStartup",1,30,Install)

concommand.Add("infmap_track_status",function()
    local report={revision=36,installed=InfMap and InfMap.TankTracksV36 or false,controllers={}}
    local viewer=LocalPlayer()
    report.viewer=IsValid(viewer) and viewer.CHUNK_OFFSET or nil
    for _,class in ipairs({"sent_tanktracks_auto","sent_tanktracks_legacy"}) do
        for _,ent in ipairs(ents.FindByClass(class)) do
            if #report.controllers>=64 then break end
            local matrix=ent.autotracks_matrix
            report.controllers[#report.controllers+1]={id=ent:EntIndex(),class=class,chunk=ent.CHUNK_OFFSET,
                native=ent:InfMap_GetPos(),viewPosition=InfMap and InfMap.TrackPosition and InfMap.TrackPosition(ent),
                matrixPosition=matrix and matrix:GetTranslation(),reset=ent.tanktracktool_reset,
                ready=ent.autotracks_data_ready,drawFrame=ent.InfMapTrackDrawChunk}
        end
    end
    file.CreateDir("infmap") file.Write("infmap/tanktracks_client_latest.json",util.TableToJSON(report,true))
    print("[InfMap tracks] installed="..tostring(report.installed).."; report: garrysmod/data/infmap/tanktracks_client_latest.json")
end)
