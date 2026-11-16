-- Stable render ownership shared by chunk rendering, P2M and Wire FLIR.
-- Never call a mutable self.OldRenderOverride from an installed wrapper.
if InfMap.RenderBridgeV28 then return end
InfMap.RenderBridgeV28 = true
local states = setmetatable({}, {__mode="k"})
local wrappers = setmetatable({}, {__mode="k"})
local function State(ent)
    local state=states[ent]
    if not state then state={} states[ent]=state end
    return state
end
local function Thermal(ent)
    return FLIR and FLIR.enabled and FLIR.RenderStack and FLIR.RenderStack[ent] and FLIR.Render
end
function InfMap.CaptureRender(ent)
    local state=State(ent)
    local current=ent.RenderOverride
    if Thermal(ent) and current==FLIR.Render then current=ent.BackupRenderOverride end
    if current==nil or (not wrappers[current] and current~=state.wrapper) then
        -- Legacy field recovery is only for the previous InfMap wrapper.
        if current and current==ent.InfMapRenderWrapper then
            local previous=ent.OldRenderOverride
            current=previous~=current and previous or nil
        end
        if not wrappers[current] and not (FLIR and current==FLIR.Render) then state.base=current end
    end
    return state.base
end
function InfMap.CommitRender(ent, wrapper)
    local state=State(ent)
    state.wrapper=wrapper
    if wrapper then wrappers[wrapper]=true end
    ent.InfMapRenderWrapper=wrapper
    ent.OldRenderOverride=state.base
    ent.ValidRenderOverride=state.base~=nil
    if Thermal(ent) then
        ent.BackupRenderOverride=wrapper or state.base
        ent.RenderOverride=FLIR.Render
    else ent.RenderOverride=wrapper or state.base end
end
-- Shared model frame for every chunk-managed entity, independent of addon/class.
-- Draw callbacks and RenderMultiply matrices remain owned by the entity.
local entityMeta=FindMetaTable and FindMetaTable("Entity")
local getLocalPos=entityMeta and entityMeta.GetLocalPos
local getLocalAngles=entityMeta and entityMeta.GetLocalAngles
function InfMap.UsesChunkRender(ent)
    return not InfMap.filter_entities(ent)
end
-- Retain the public helper names used by earlier compatibility adapters.
InfMap.IsRenderProp=InfMap.UsesChunkRender
function InfMap.PropNativePose(ent)
    local pos,ang=vector_origin,angle_zero
    local current=ent
    local nativeParent=false
    for _=1,64 do
        -- Bone/attachment parenting has an additional engine transform which
        -- cannot be reconstructed from parent-local origins alone.
        if current.GetParentAttachment and current:GetParentAttachment()>0 then nativeParent=true end
        if current.GetParentBone and current:GetParentBone()>=0 then nativeParent=true end
        local lp=getLocalPos and getLocalPos(current) or current:GetLocalPos()
        local la=getLocalAngles and getLocalAngles(current) or current:GetLocalAngles()
        pos,ang=LocalToWorld(pos,ang,lp,la)
        local parent=current:GetParent()
        if not IsValid(parent) then
            if nativeParent then pos=ent:InfMap_GetPos() ang=ent:GetAngles() end
            return pos,ang,current.CHUNK_OFFSET or ent.CHUNK_OFFSET
        end
        current=parent
    end
    -- A malformed/cyclic parent graph must not hang rendering.
    return ent:InfMap_GetPos(),ent:GetAngles(),ent.CHUNK_OFFSET
end
function InfMap.DrawChunkEntity(ent, offset, base, flags)
    local state=State(ent)
    if state.drawing then return end
    state.drawing=true
    local override=ent.RenderOverride
    -- Native DrawModel calls from P2M/other callbacks must not re-enter the
    -- wrapper/FLIR chain. The source draw callback is captured by the closure.
    ent.RenderOverride=nil
    -- Viewer chunks may change after PreRender (or mutate the same Vector).
    -- Resolve the entity/root frame at draw time, not wrapper installation.
    local propPos,propAng,propChunk
    if InfMap.IsRenderProp(ent) then propPos,propAng,propChunk=InfMap.PropNativePose(ent) end
    if ent.InfMapP2MChunk or propChunk then
        local chunk=ent.InfMapP2MChunk and ent:InfMapP2MChunk() or propChunk
        local viewer=LocalPlayer()
        if chunk and IsValid(viewer) and viewer.CHUNK_OFFSET then
            offset=(chunk-viewer.CHUNK_OFFSET)*(InfMap.chunk_size*2)
        end
    end
    local shifted=offset and offset~=vector_origin
    if shifted then cam.Start3D(EyePos()-offset) end
    -- Ragdolls own multiple physics/bone poses; shifting the camera is enough.
    -- Addons with an independent render pose can retain it through this flag.
    local setPose=propPos and not (ent.IsRagdoll and ent:IsRagdoll()) and not ent.InfMapKeepRenderPose
    local oldOrigin,oldAngles
    if setPose then oldOrigin=ent:GetRenderOrigin() oldAngles=ent:GetRenderAngles() end
    local ok,err=xpcall(function()
        if setPose then
            ent:SetRenderOrigin(propPos) ent:SetRenderAngles(propAng)
            ent:InvalidateBoneCache() ent:SetupBones()
        end
        if ent.InfMapP2MDraw then ent:InfMapP2MDraw(flags)
        elseif base then base(ent,flags)
        else ent:DrawModel(flags) end
    end,debug.traceback)
    if setPose then
        ent:SetRenderOrigin(oldOrigin) ent:SetRenderAngles(oldAngles)
        ent:InvalidateBoneCache()
    end
    if shifted then cam.End3D() end
    ent.RenderOverride=override
    state.drawing=nil
    if not ok and (not state.errorTime or RealTime()-state.errorTime>5) then
        state.errorTime=RealTime() ErrorNoHalt(tostring(err).."\n")
    end
end
local function InstallFLIR()
    if not FLIR or not FLIR.Render or InfMap.WireFLIRRenderFixed then return end
    local previous=FLIR.Render
    FLIR.Render=function(ent,flags)
        if FLIR.hide then return end
        local backup=ent.BackupRenderOverride
        -- An InfMap backup already owns the coordinate shift and complete draw.
        -- Wire's original extra DrawModel would draw the native copy a second time.
        if backup and backup~=FLIR.Render and backup~=previous then
            if wrappers[backup] then return backup(ent,flags) end
            return InfMap.DrawChunkEntity(ent,nil,backup,flags)
        end
        return InfMap.DrawChunkEntity(ent,nil,nil,flags)
    end
    for ent in pairs(FLIR.RenderStack or {}) do
        if IsValid(ent) and ent.RenderOverride==previous then ent.RenderOverride=FLIR.Render end
    end
    InfMap.WireFLIRRenderFixed=true
end
hook.Add("InitPostEntity","InfMapWireFLIRRender",InstallFLIR)
timer.Simple(0,InstallFLIR)
timer.Create("InfMapWireFLIRRenderStartup",1,30,function()
    InstallFLIR()
    if InfMap.WireFLIRRenderFixed then timer.Remove("InfMapWireFLIRRenderStartup") end
end)
