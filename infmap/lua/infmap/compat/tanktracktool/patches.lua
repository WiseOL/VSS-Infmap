-- Adapt the installed, CRC-verified Tank Track Tool source at runtime.
-- The addon source itself is not bundled or redistributed here.
local function Replace(source,from,to)
    local result,cursor={},1
    while true do
        local first,last=source:find(from,cursor,true)
        if not first then result[#result+1]=source:sub(cursor) return table.concat(result) end
        result[#result+1]=source:sub(cursor,first-1) result[#result+1]=to cursor=last+1
    end
end
function InfMap.BuildTrackAdapter(name,source)
    if name~="mode" then
        source=Replace(source,'include( "shared.lua" )',"")
        source=Replace(source,'DEFINE_BASECLASS( "base_tanktracktool" )','local BaseClass=baseclass.Get("base_tanktracktool")')
        source=source:gsub("([%w_%.]+):GetWorldTransformMatrix%(%)","InfMap.TrackMatrix(%1)")
        source=source:gsub("([%w_%.]+):GetPos%(%)","InfMap.TrackPosition(%1)")
    end
    if name=="mode" then
        for _,side in ipairs({"le","ri"}) do
            source=Replace(source,"csent:SetPos( self."..side.."_posworld )","csent.InfMapTrackPosition = self."..side.."_posworld")
        end
        source=Replace(source,"csent:DrawModel()","InfMap.DrawTrackModel(csent,csent.InfMapTrackPosition,csent:GetAngles())")
        source=Replace(source,"    function meta:draw( controller )\n","    function meta:draw( controller )\n        InfMap.RefreshTrackDraw(controller)\n")
        source=Replace(source,"        self:onThink( controller, eyepos, eyedir )\n","        self:onThink( controller, eyepos, eyedir )\n        InfMap.MarkTrackFrame(controller)\n")
    elseif name=="legacy" then
        source=Replace(source,"emptyCSENT:SetPos( pos )","emptyCSENT.InfMapTrackPosition = pos")
        source=Replace(source,"emptyCSENT:DrawModel()","InfMap.DrawTrackModel(emptyCSENT,pos,ang)")
    elseif name=="auto" then
        source=Replace(source,"    BaseClass.Think( self )","    InfMap.RebaseTrackHistory(self)\n    BaseClass.Think( self )")
        for _,field in ipairs({"wheel.le_trace","wheel.ri_trace","wheel_trace"}) do
            source=Replace(source,"util.TraceHull( "..field.." )","InfMap.TrackHull( "..field.." )")
        end
    else error("Unknown track adapter: "..tostring(name),0) end
    return source
end
