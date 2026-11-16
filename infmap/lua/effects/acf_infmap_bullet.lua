-- Derived from ACF 3 (MIT); global simulation, viewer-relative rendering.

local ACF       = ACF
local Bullets   = ACF.BulletEffect
local Clock     = ACF.Utilities.Clock
local function ViewerPosition(pos)
    if not InfMap then return pos end
    return pos - InfMap.unlocalize_vector(Vector(), LocalPlayer().CHUNK_OFFSET)
end

function EFFECT:Init(Data)
	self.Index = Data:GetDamageType()
	self.ExpireTime = RealTime() + 15

	self:SetModel("models/acf/munitions/projectile.mdl")

	if not self.Index then
		self.Kill = true

		return
	end
	local pending = ACF.InfMapPendingEffects[self.Index]
	if not pending or pending.generation ~= Data:GetMagnitude() then
		self.Kill = true
		return
	end
	ACF.InfMapReleasePending(self.Index)

	self.CreateTime = Clock.CurTime

	local CanDraw = Data:GetAttachment() > 0
	local Bullet  = Bullets[self.Index]
	local Flight  = Data:GetStart() * 10
	local Origin  = Data:GetOrigin()
	local Hit     = Data:GetScale()

	-- Scale encodes the hit type, so if it's 0 it's a new bullet, else it's an update so we need to remove the effect
	if Hit > 0 then
		self.Kill = true
		return
	end
	if Bullet then ACF.InfMapCleanupBullet(self.Index) end
	if ACF.InfMapActiveEffects >= 256 then self.Kill = true return end
	do
		local Crate = Data:GetEntity()

		--TODO: Check if it is actually a crate
		if not IsValid(Crate) then
			self.Kill = true

			return
		end

		-- TODO: Force crates to network and store this information on the client when they're created
		local Suffix = ACF.GetCrateNWSuffix and ACF.GetCrateNWSuffix(Data:GetFlags()) or ""
		local Tracer  = Crate:GetNW2Float("Tracer" .. Suffix) > 0
		local Caliber = Crate:GetNW2Float("Caliber" .. Suffix, 10)
		local BulletData = {
			Index         = self.Index,
			Crate         = Crate,
			SimFlight     = Flight,
			SimPos        = Origin,
			SimPosLast    = Origin,
			Caliber       = Caliber,
			RoundMass     = Crate:GetNW2Float("ProjMass" .. Suffix, 10),
			FillerMass    = Crate:GetNW2Float("FillerMass" .. Suffix),
			WPMass        = Crate:GetNW2Float("WPMass" .. Suffix),
			DragCoef      = Crate:GetNW2Float("DragCoef" .. Suffix, 1),
			AmmoType      = Crate:GetNW2String("AmmoType" .. Suffix, "ACF.Ammunition.AP"),
			Tracer        = Tracer and ParticleEmitter(ViewerPosition(Origin)) or nil,
			Color         = Tracer and Crate:GetColor() or nil,
			Accel         = Crate:GetNW2Vector("Accel" .. Suffix, ACF.Gravity),
			LastThink     = Clock.CurTime,
			Effect        = self,
		}

		--Add all that data to the bullet table, overwriting if needed
		local impact = ACF.InfMapImpactBullets and ACF.InfMapImpactBullets[self.Index]
		if impact then BulletData.Detonated = impact.bullet.Detonated end
		BulletData.InfMapExpireTime = self.ExpireTime
		BulletData.InfMapManaged = true
		ACF.InfMapActiveEffects = ACF.InfMapActiveEffects + 1
		Bullets[self.Index] = BulletData

		-- Set model and bodygroup based on ammo type
		local FlightModel = Crate:GetNW2String("FlightModel" .. Suffix, "")
		if FlightModel ~= "" then
			self:SetModel(FlightModel)
			self:SetBodygroup(0, Crate:GetNW2Int("FlightBodygroup" .. Suffix, 0))
		end

		self:SetPos(ViewerPosition(Origin))
		self:SetAngles(Flight:Angle())
		self:SetModelScale(Caliber * 0.1, 0)

		self.DrawEffect = CanDraw

		hook.Run("ACF_OnCreateBulletEffect", self, BulletData)
	end
end

function EFFECT:Think()
	local Bullet = Bullets[self.Index]

	-- An old effect must never claim or delete a new bullet reusing its index.
	if not Bullet or Bullet.Effect ~= self then return false end
	if not self.Kill and RealTime() < self.ExpireTime then return true end
	ACF.InfMapCleanupBullet(self.Index, self)

	return false
end

function EFFECT:ApplyMovement(Bullet)
	local Position = ViewerPosition(Bullet.SimPos)
	if math.abs(Position.x) > 16380 or math.abs(Position.y) > 16380 or math.abs(Position.z) > 16380 then
		self.DrawOutside = true
		return
	end
	self.DrawOutside = false

	--Moving the effect to the calculated position
	if Position.z < 16380 then
		self:SetPos(Position)
		self:SetAngles(Bullet.SimFlight:Angle())
	end

	if not self.DrawEffect then return end

	if Bullet.Tracer and IsValid(Bullet.Tracer) then
		local DeltaPos = Position - ViewerPosition(Bullet.SimPosLast)
		local Length = math.max(DeltaPos:Length() * 2, 1)
		local MaxSprites = 2
		local Light = Bullet.Tracer:Add("sprites/acf_tracer.vmt", ViewerPosition(Bullet.SimPosLast))

		if Light then
			local Color = Bullet.Color

			Light:SetAngles(Bullet.SimFlight:Angle())
			Light:SetVelocity(Bullet.SimFlight:GetNormalized())
			Light:SetColor(Color.r, Color.g, Color.b)
			Light:SetDieTime(0.075)
			Light:SetStartAlpha(255)
			Light:SetEndAlpha(0)
			Light:SetStartSize(Bullet.Caliber * 15)
			Light:SetEndSize(Bullet.Caliber * 15)
			Light:SetStartLength(Length)
			Light:SetEndLength(Length)
		end

		for i = 1, MaxSprites do
			local Smoke = Bullet.Tracer:Add("particle/smokesprites_000" .. math.random(1, 9), Position - (DeltaPos * i / MaxSprites))

			if Smoke then
				Smoke:SetAngles(Bullet.SimFlight:Angle())
				Smoke:SetVelocity(Bullet.SimFlight * 0.05)
				Smoke:SetColor(200, 200, 200)
				Smoke:SetDieTime(0.6)
				Smoke:SetStartAlpha(10)
				Smoke:SetEndAlpha(0)
				Smoke:SetStartSize(1)
				Smoke:SetEndSize(Length * Bullet.Caliber * 0.0025)
				Smoke:SetRollDelta(0.1)
				Smoke:SetAirResistance(150)
				Smoke:SetGravity(Vector(0, 0, 20))
			end
		end
	end
end

function EFFECT:Render()
	if not self.DrawEffect or self.DrawOutside then return end

	self:DrawModel()
end
