-- ACF-Team P2M controllers use a clientside child for basic + split meshes.
-- Keep the parent-local transform and render the COMPLETE Draw callback once.
-- GetLocalPos/Angles have no InfMap world-coordinate detour. For an
-- unparented root these are the interpolated native origin/angles, avoiding
-- any entity-specific GetPos alias or client world-pose cache.
local meta=FindMetaTable and FindMetaTable("Entity")
local localPosition=meta and meta.GetLocalPos
local localAngles=meta and meta.GetLocalAngles
local function LocalPosition(ent) return localPosition and localPosition(ent) or ent:GetLocalPos() end
local function LocalAngles(ent) return localAngles and localAngles(ent) or ent:GetLocalAngles() end
local meshes=setmetatable({}, {__mode="k"})
local function Register(ent)
    if IsValid(ent) and ent:GetClass()=="sent_prop2mesh" then meshes[ent]=true end
end
local function RegisterAll()
    for _,ent in ipairs(ents.FindByClass("sent_prop2mesh")) do Register(ent) end
end
hook.Add("OnEntityCreated","InfMapP2MRegister",function(ent)
    if ent:GetClass()=="sent_prop2mesh" then timer.Simple(0,function() Register(ent) end) end
end)
hook.Add("InitPostEntity","InfMapP2MRegister",RegisterAll)
timer.Simple(0,RegisterAll)
local function ParentChunk(parent)
    local root=parent
    for _=1,64 do
        local nextParent=root:GetParent()
        if not IsValid(nextParent) then return root.CHUNK_OFFSET or parent.CHUNK_OFFSET end
        root=nextParent
    end
end
local function NativePose(self)
    local info=self.InfMapP2MInfo
    if not info then return end
    local mesh=self.InfMapP2MOwner
    local parent=IsValid(info.linkent) and info.linkent or mesh
    if not IsValid(parent) then return end
    local pos,ang=info.linkpos or vector_origin,info.linkang or angle_zero
    for _=1,64 do
        local nextParent=parent:GetParent()
        if not IsValid(nextParent) then
            local worldPos,worldAng=LocalToWorld(pos,ang,LocalPosition(parent),LocalAngles(parent))
            return worldPos,worldAng,parent.CHUNK_OFFSET,parent
        end
        pos,ang=LocalToWorld(pos,ang,LocalPosition(parent),LocalAngles(parent))
        parent=nextParent
    end
end
local function LiveChunk(self)
    local info=self.InfMapP2MInfo
    local parent=info and IsValid(info.linkent) and info.linkent or self.InfMapP2MOwner
    if IsValid(parent) then return ParentChunk(parent) end
end
local function DrawController(self,flags)
    local disabled=GetConVar and GetConVar("prop2mesh_render_disable")
    if disabled and disabled:GetBool() then return end
    local info=self.InfMapP2MInfo
    local clips=info and info.clips
    local count=clips and #clips or 0
    local nativePos,nativeAng=NativePose(self)
    if not nativePos then return end
    local oldOrigin=self:GetRenderOrigin()
    local oldAngles=self:GetRenderAngles()
    local clipping,pushed,matrixPushed=nil,0,false
    if count>0 then clipping=render.EnableClipping(true) end
    local ok,err=xpcall(function()
        self:SetRenderOrigin(nativePos)
        self:SetRenderAngles(nativeAng)
        self:InvalidateBoneCache()
        self:SetupBones()
        if count>0 then
            -- The camera is shifted into the native frame, so clip positions
            -- must use native coordinates too, not viewer-relative GetPos().
            local pos,ang=nativePos,nativeAng
            for _,clip in ipairs(clips) do
                local normal=Vector(clip.n)
                normal:Rotate(ang)
                render.PushCustomClipPlane(normal,normal:Dot(pos+normal*clip.d))
                pushed=pushed+1
            end
        end
        -- DrawModel obtains P2M's basic GetRenderMesh. Complex pieces use an
        -- explicit matrix, never the possibly stale child world matrix.
        self:DrawModel(flags)
        local recycled=prop2mesh and prop2mesh.recycle and prop2mesh.recycle[info.crc]
        local data=recycled and recycled.meshes and recycled.meshes[info.uniqueID]
        if data and data.complex then
            local matrix=Matrix()
            matrix:SetTranslation(nativePos)
            matrix:SetAngles(nativeAng)
            if info.scale then matrix:SetScale(info.scale) end
            cam.PushModelMatrix(matrix) matrixPushed=true
            for _,part in ipairs(data.complex) do part:Draw() end
            cam.PopModelMatrix() matrixPushed=false
        end
    end,debug.traceback)
    if matrixPushed then cam.PopModelMatrix() end
    for _=1,pushed do render.PopCustomClipPlane() end
    self:SetRenderOrigin(oldOrigin)
    self:SetRenderAngles(oldAngles)
    self:InvalidateBoneCache()
    if clipping~=nil then render.EnableClipping(clipping) end
    if not ok then error(err,0) end
end
local function MeshBounds(child,info)
    local recycled=prop2mesh and prop2mesh.recycle and prop2mesh.recycle[info.crc]
    local data=recycled and recycled.meshes and recycled.meshes[info.uniqueID]
    if not data or not data.vmins or not data.vmaxs then return end
    local scale=info.scale or Vector(1,1,1)
    local lo,hi=data.vmins,data.vmaxs
    local minx,maxx=math.min(lo.x*scale.x,hi.x*scale.x),math.max(lo.x*scale.x,hi.x*scale.x)
    local miny,maxy=math.min(lo.y*scale.y,hi.y*scale.y),math.max(lo.y*scale.y,hi.y*scale.y)
    local minz,maxz=math.min(lo.z*scale.z,hi.z*scale.z),math.max(lo.z*scale.z,hi.z*scale.z)
    local saved=child.RENDER_BOUNDS
    if not saved or saved[1].x~=minx or saved[1].y~=miny or saved[1].z~=minz
        or saved[2].x~=maxx or saved[2].y~=maxy or saved[2].z~=maxz then
        local minimum,maximum=Vector(minx,miny,minz),Vector(maxx,maxy,maxz)
        child.RENDER_BOUNDS={minimum,maximum}
        child:SetRenderBounds(minimum,maximum)
    end
end
hook.Add("PreRender","InfMapP2MSync",function()
    local viewer=LocalPlayer()
    if not IsValid(viewer) or not viewer.CHUNK_OFFSET then return end
    local chunks={}
    for mesh in pairs(meshes) do
        if not IsValid(mesh) then meshes[mesh]=nil
        else
            for _,info in pairs(mesh.prop2mesh_controllers or {}) do
                local child=info.ent
                local parent=IsValid(info.linkent) and info.linkent or mesh
                if IsValid(child) then
                    local changed=child.InfMapP2MDraw~=DrawController
                    child.InfMapP2MSourceDraw=child.Draw
                    child.InfMapP2MOwner=mesh
                    child.InfMapP2MChunk=LiveChunk
                    child.InfMapP2MNativePose=NativePose
                    child.InfMapP2MDraw=DrawController
                    child.InfMapP2MInfo=info
                    local chunk=chunks[parent] or ParentChunk(parent)
                    chunks[parent]=chunk
                    if chunk then
                        local localPos,localAng=info.linkpos or vector_origin,info.linkang or angle_zero
                        if child:GetParent()~=parent then child:SetParent(parent) end
                        if child:GetLocalPos()~=localPos then child:SetLocalPos(localPos) end
                        if child:GetLocalAngles()~=localAng then child:SetLocalAngles(localAng) end
                        MeshBounds(child,info)
                        local flir=FLIR and FLIR.enabled and FLIR.RenderStack and FLIR.RenderStack[child]
                        local current=flir and child.RenderOverride==FLIR.Render and child.BackupRenderOverride or child.RenderOverride
                        local replaced=current~=child.InfMapRenderWrapper
                        if changed or child.CHUNK_OFFSET~=chunk or child.InfMapP2MViewerChunk~=viewer.CHUNK_OFFSET or replaced then
                            InfMap.prop_update_chunk(child,chunk)
                            child.InfMapP2MViewerChunk=Vector(viewer.CHUNK_OFFSET)
                        end
                    end
                end
            end
        end
    end
end)

-- On-demand evidence if an external addon still changes the controller frame.
concommand.Add("infmap_p2m_status",function()
    local function Vec(v) if v then return {x=v.x,y=v.y,z=v.z} end end
    local report={revision=31,chunkSize=InfMap.chunk_size,viewer=Vec(IsValid(LocalPlayer()) and LocalPlayer().CHUNK_OFFSET),controllers={}}
    for mesh in pairs(meshes) do
        if IsValid(mesh) then
            for _,info in pairs(mesh.prop2mesh_controllers or {}) do
                local child=info.ent
                if IsValid(child) and #report.controllers<128 then
                    local pos,ang,chunk,root=NativePose(child)
                    report.controllers[#report.controllers+1]={mesh=mesh:EntIndex(),child=child:EntIndex(),
                        chunk=Vec(chunk),childChunk=Vec(child.CHUNK_OFFSET),cachedNative=Vec(child:InfMap_GetPos()),
                        composedNative=Vec(pos),linkPosition=Vec(info.linkpos),
                        root=IsValid(root) and root:EntIndex() or nil,
                        rootLocal=IsValid(root) and Vec(LocalPosition(root)) or nil,
                        rootAlias=IsValid(root) and Vec(root:InfMap_GetPos()) or nil,
                        rootNetwork=IsValid(root) and root.GetNetworkOrigin and Vec(root:GetNetworkOrigin()) or nil,
                        childLocal=Vec(LocalPosition(child))}
                end
            end
        end
    end
    file.CreateDir("infmap")
    file.Write("infmap/p2m_client_latest.json",util.TableToJSON(report,true))
    print("[InfMap P2M] Client controller poses saved to data/infmap/p2m_client_latest.json")
end)
