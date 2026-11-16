if not InfMap.RenderBridgeV28 then include("infmap/cl_inf_00_render.lua") end
// this has to be forced in order for render overrides to work
hook.Add("InitPostEntity", "inf_init", function()
	LocalPlayer():ConCommand("cl_drawspawneffect 0")
end)

local too_far = 100 * 100	// how far away before you just stop rendering entirely ^2
local empty_function = function() end

// detour render bounds of entities in other chunks
// needs to be updated every tick since the offset is not local to the prop
// which entities should be checked per frame
InfMap.all_ents = {}
local listed = setmetatable({}, {__mode = "k"})
local function update_ents(all)
    if all then
        InfMap.all_ents = ents.GetAll()
        listed = setmetatable({}, {__mode = "k"})
        for _, ent in ipairs(InfMap.all_ents) do listed[ent] = true end
        return
    end
    local lpco = LocalPlayer().CHUNK_OFFSET
    local write = 1
    for read = 1, #InfMap.all_ents do
        local ent = InfMap.all_ents[read]
        local valid = IsValid(ent) and ent.CHUNK_OFFSET and lpco
        valid = valid and not InfMap.filter_entities(ent)
        valid = valid and ent.RenderOverride and ent.RenderOverride ~= empty_function
        valid = valid and not ent:GetNoDraw()
        valid = valid and (ent.CHUNK_OFFSET - lpco):LengthSqr() <= too_far
        if valid then
            InfMap.all_ents[write] = ent
            write = write + 1
        else listed[ent] = nil end
    end
    for i = #InfMap.all_ents, write, -1 do InfMap.all_ents[i] = nil end
end

local update_all = false
timer.Create("infinite_chunkmove_update", 0.5, 0, function()
	update_ents(true)
	update_all = true
end)


hook.Add("RenderScene", "!infinite_update_visbounds", function(eyePos, eyeAngles)
	//eyePos = LocalPlayer():GetShootPos()
	local sub_size = (InfMap.source_bounds[1] - InfMap.chunk_size) * 0.5	// how far out render bounds can be before outside of the map
	local lp_chunk_offset = LocalPlayer().CHUNK_OFFSET
	if !lp_chunk_offset then return end
	for _, ent in ipairs(InfMap.all_ents) do	// I feel bad for doing this
		if !IsValid(ent) then continue end
		if !ent.RenderOverride then continue end
		if !ent.CHUNK_OFFSET then continue end

		// when bounding box is outside of world bounds the object isn't rendered
		// to combat this we locally "shrink" the bounds so they are right infront of the players eyes
        local propPos,propAng,propChunk
        if InfMap.UsesChunkRender(ent) then propPos,propAng,propChunk=InfMap.PropNativePose(ent) end
        local renderChunk=ent.InfMapP2MChunk and ent:InfMapP2MChunk() or propChunk or ent.CHUNK_OFFSET
        local world_chunk_offset=renderChunk-lp_chunk_offset
		if world_chunk_offset == vector_origin then
            if ent.RENDER_BOUNDS then ent:SetRenderBounds(ent.RENDER_BOUNDS[1],ent.RENDER_BOUNDS[2]) end
            continue
        end
		if world_chunk_offset:LengthSqr() > too_far then continue end	// too far, dont render

        -- Culling must follow the exact pose used by the P2M draw. Its cached
        -- child GetPos can be whole chunks away from the actual parent pose.
        local nativePos=ent.InfMapP2MNativePose and ent:InfMapP2MNativePose() or propPos or ent:InfMap_GetPos()
        if not nativePos then continue end
        local prop_dir=InfMap.unlocalize_vector(nativePos,world_chunk_offset)-eyePos

		//local shrunk = !far_lod and 0.02 or sub_size / prop_dir:Length()
		local shrunk = sub_size / prop_dir:Length()	// how much you locally shrink render bounds [in reality should be chunksize / prop_dir:Length()]
		prop_dir = prop_dir * shrunk

		// grab render bounds in case its been edited (prop resizer compatability)
		if !ent.RENDER_BOUNDS then 
			local min, max = ent:GetRenderBounds() 
			ent.RENDER_BOUNDS = {min, max}
		end

		if world_chunk_offset:LengthSqr() > 16 then
			ent:SetRenderBoundsWS(eyePos + prop_dir, eyePos + prop_dir)
		else
			// if entity angle is perfectly 0,0,0 GetRotatedAABB returns Vector(),Vector() for some reason
			local min, max
			if ent:GetAngles() != Angle() then	
				min, max = ent:GetRotatedAABB(ent.RENDER_BOUNDS[1], ent.RENDER_BOUNDS[2])
			else
				min, max = ent.RENDER_BOUNDS[1], ent.RENDER_BOUNDS[2]
			end

			min = min * shrunk
			max = max * shrunk
			ent:SetRenderBoundsWS(eyePos + prop_dir + min, eyePos + prop_dir + max)
			//debugoverlay.Box(eyePos + prop_dir, min, max, 0, Color(0, 0, 255, 0))
		end
	end

	if update_all then 
		update_ents()
		update_all = false
	end
end)

// debug cache
local debug_enabled = CreateClientConVar("infmap_debug", "0", true, false)
local maxsize = InfMap.source_bounds
local black = Color(0, 0, 0, 0)
local red = Color(255, 0, 0, 255)
local blue = Color(0, 0, 255, 255)

// players just.. dont want to render? force rendering..
hook.Add("PostDrawOpaqueRenderables", "infinite_player_render", function()
	if !LocalPlayer().CHUNK_OFFSET then return end
	local chunk_offset = LocalPlayer().CHUNK_OFFSET
	for k, v in ipairs(player.GetAll()) do
		if !v:Alive() then continue end
		if v.CHUNK_OFFSET != chunk_offset then
			v:RemoveEffects(EF_DIMLIGHT)	// force flashlight off if in another chunk
		end
		v:DrawModel()
	end

	// debug lines
	if !debug_enabled:GetBool() then return end

	local cs = Vector(1, 1, 1) * InfMap.chunk_size
	local co =  chunk_offset * InfMap.chunk_size * 2
	
	render.DrawWireframeSphere(Vector(), 10, 10, 10, red, true)
	render.DrawWireframeBox(Vector(), Angle(), -cs, cs, black, true)
	
	render.DrawWireframeBox(Vector(), Angle(), -cs - co, cs - co, black, true)
	render.DrawWireframeBox(Vector(), Angle(), -maxsize - co, maxsize - co, blue, true)
end)

// server tells clients when a prop has entered another chunk
// detour rendering of entities in other chunks
function InfMap.prop_update_chunk(ent, chunk)
	local prev_chunk = ent.CHUNK_OFFSET
	ent.CHUNK_OFFSET = chunk
	if prev_chunk != chunk then ent:CollisionRulesChanged() end

	// addons may error when calling this
	local err, str = pcall(function() hook.Run("PropUpdateChunk", ent, chunk, prev_chunk) end)
	if !err then ErrorNoHalt(str) end
	
	// loop through all ents, offset them relative to player since player has moved
	if ent == LocalPlayer() then 
		for k, v in ipairs(ents.GetAll()) do 
			local min_bound, max_bound = v:GetModelRenderBounds()
			if !min_bound or !max_bound then continue end
			if v == ent or InfMap.filter_entities(v) then continue end
			//v.CHUNK_OFFSET = v.CHUNK_OFFSET or prev_chunk	// corpse support
			if !v.CHUNK_OFFSET then continue end

			InfMap.prop_update_chunk(v, v.CHUNK_OFFSET)
		end
		return 
	end

	// clientside models support
	for _, parent in ipairs(ent:GetChildren()) do
		if parent:EntIndex() != -1 then continue end
		InfMap.prop_update_chunk(parent, chunk)	// update renderoverride
	end

	// when first spawning in props will attempt to render offset before client has initialized
	// after prop chunks have been networked to client we initalize them and therefore update all prop rendering
	if !IsValid(LocalPlayer()) or InfMap.filter_entities(ent) then return end

	// offset single prop relative to player, only the prop has moved
    if not chunk or not LocalPlayer().CHUNK_OFFSET then return end
    local sourceDraw = InfMap.CaptureRender(ent)
	local chunk_offset = chunk - LocalPlayer().CHUNK_OFFSET

    // Keep a managed wrapper in the same chunk too. Its live frame remains
    // correct if either entity moves before a chunk notification is processed.

	//print("Detouring rendering of entity:", ent)

	// put ent in table to update renderbounds
	if not listed[ent] then
        listed[ent] = true
        InfMap.all_ents[#InfMap.all_ents + 1] = ent
    end

	// physgun glow and beam can be seen from any chunk
	// turn physgun off by setting its color to negative infinity if its not in our chunk
	if ent:IsPlayer() and chunk_offset != vector_origin then
		ent.ORIGINAL_PHYSGUN_COLOR = ent.ORIGINAL_PHYSGUN_COLOR or ent:GetWeaponColor()
		ent:SetWeaponColor(Vector(-math.huge, -math.huge, -math.huge))
    elseif ent:IsPlayer() and ent.ORIGINAL_PHYSGUN_COLOR then
        ent:SetWeaponColor(ent.ORIGINAL_PHYSGUN_COLOR)
        ent.ORIGINAL_PHYSGUN_COLOR=nil
    end

    local visual_offset=chunk_offset*(InfMap.chunk_size*2)
    local draw=sourceDraw
    local mat
    local wrapper=function(self,flags)
        local pos,ang,liveChunk=InfMap.PropNativePose(self)
        if self.InfMapP2MChunk then liveChunk=self:InfMapP2MChunk() end
        local viewer=LocalPlayer()
        local viewerChunk=IsValid(viewer) and viewer.CHUNK_OFFSET
        local relative=liveChunk and viewerChunk and liveChunk-viewerChunk or chunk_offset
        local len=relative:LengthSqr()
        if len>too_far then return end
        -- Resolve LOD every draw: an old hidden/box wrapper must not survive
        -- a root/viewer transition just because a notification was missed.
        if len>100 and not self:IsPlayer() and not self.InfMapP2MDraw then
            if self:BoundingRadius()<10 or self:IsWeapon() then return end
            if not mat then
                local name=self:GetMaterials()[1] or self:GetMaterial()
                if not name or #name==0 then return end
                mat=Material(name)
            end
            render.SetMaterial(mat)
            render.DrawBox(pos+relative*(InfMap.chunk_size*2),ang,self:OBBMins(),self:OBBMaxs())
            return
        end
        InfMap.DrawChunkEntity(self,visual_offset,draw,flags)
    end
    if chunk_offset==vector_origin and ent.RENDER_BOUNDS then
        ent:SetRenderBounds(ent.RENDER_BOUNDS[1],ent.RENDER_BOUNDS[2])
    end
    InfMap.CommitRender(ent,wrapper)
end
