-- Track simulation and mesh matrices use a single viewer-relative frame.
function InfMap.TrackPosition(ent)
    local pos,_,chunk=InfMap.PropNativePose(ent)
    local viewer=LocalPlayer()
    if chunk and IsValid(viewer) and viewer.CHUNK_OFFSET then
        return pos+(chunk-viewer.CHUNK_OFFSET)*(InfMap.chunk_size*2)
    end
    return pos
end
function InfMap.TrackMatrix(ent)
    local matrix=Matrix(ent:GetWorldTransformMatrix())
    matrix:SetTranslation(InfMap.TrackPosition(ent))
    return matrix
end
function InfMap.RebaseTrackHistory(ent)
    local viewer=LocalPlayer()
    if not IsValid(viewer) or not viewer.CHUNK_OFFSET then return end
    local chunk=viewer.CHUNK_OFFSET
    local previous=ent.InfMapTrackViewerChunk
    if previous and previous~=chunk then
        local shift=(previous-chunk)*(InfMap.chunk_size*2)
        if ent.autotracks_le_lastpos then ent.autotracks_le_lastpos=ent.autotracks_le_lastpos+shift end
        if ent.autotracks_ri_lastpos then ent.autotracks_ri_lastpos=ent.autotracks_ri_lastpos+shift end
    end
    ent.InfMapTrackViewerChunk=Vector(chunk)
end
-- Global-hook client models have no networked chunk. Draw them in a bounded
-- native frame and restore their state rather than passing positions to SetPos.
function InfMap.DrawTrackModel(ent,pos,ang)
    if not IsValid(ent) or not pos then return end
    local native,relative=InfMap.localize_vector(pos)
    local offset=relative*(InfMap.chunk_size*2)
    local origin,angles,override=ent:GetRenderOrigin(),ent:GetRenderAngles(),ent.RenderOverride
    local shifted=offset~=vector_origin
    if shifted then cam.Start3D(EyePos()-offset) end
    local ok,err=xpcall(function()
        ent.RenderOverride=nil
        ent:SetRenderOrigin(native) ent:SetRenderAngles(ang)
        ent:InvalidateBoneCache() ent:SetupBones() ent:DrawModel()
    end,debug.traceback)
    ent:SetRenderOrigin(origin) ent:SetRenderAngles(angles)
    ent:InvalidateBoneCache() ent.RenderOverride=override
    if shifted then cam.End3D() end
    if not ok then error(err,0) end
end
-- Only the track tool's short visual suspension probes use this adapter.
-- Preserve the original filter and query the probe's chunk, not the viewer's.
function InfMap.TrackHull(data)
    local start,relative=InfMap.localize_vector(data.start)
    local offset=relative*(InfMap.chunk_size*2)
    local viewer=LocalPlayer()
    local chunk=relative+(IsValid(viewer) and viewer.CHUNK_OFFSET or vector_origin)
    local query={}
    for k,v in pairs(data) do query[k]=v end
    query.start=start query.endpos=data.endpos-offset
    local original=data.filter
    query.filter=function(ent)
        if IsValid(ent) and ent.CHUNK_OFFSET and ent.CHUNK_OFFSET~=chunk then return false end
        if type(original)=="function" then return original(ent) end
        if original==ent then return false end
        if type(original)=="table" then for _,ignore in pairs(original) do if ignore==ent then return false end end end
        return true
    end
    -- Raw client hull trace; util.TraceHull filters to the viewer chunk.
    local result=InfMap.TraceHull(query)
    if result.HitPos then result.HitPos=result.HitPos+offset end
    if result.StartPos then result.StartPos=result.StartPos+offset end
    return result
end

function InfMap.MarkTrackFrame(ent)
    local viewer=LocalPlayer()
    if IsValid(viewer) and viewer.CHUNK_OFFSET then ent.InfMapTrackDrawChunk=Vector(viewer.CHUNK_OFFSET) end
end
function InfMap.RefreshTrackDraw(ent)
    local viewer=LocalPlayer()
    local previous=ent.InfMapTrackDrawChunk
    if not previous or not IsValid(viewer) or not viewer.CHUNK_OFFSET then return end
    local current=viewer.CHUNK_OFFSET
    if previous==current then return end
    local shift=(previous-current)*(InfMap.chunk_size*2)
    local matrix=ent.autotracks_matrix
    if matrix then matrix:SetTranslation(matrix:GetTranslation()+shift) end
    local data=ent.tanktracktool_modeData
    local function ShiftPart(part)
        if part.le_posworld then part.le_posworld=part.le_posworld+shift end
        if part.ri_posworld then part.ri_posworld=part.ri_posworld+shift end
    end
    if data and data.parts then
        for _,part in ipairs(data.parts) do
            ShiftPart(part)
            -- Assembly modes store indexed child parts; legacy uses flat nodes.
            if part.parts then for _,child in ipairs(part) do ShiftPart(child) end end
        end
    end
    ent.InfMapTrackDrawChunk=Vector(current)
end
