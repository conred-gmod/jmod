﻿-- AdventureBoots Late 2021
AddCSLuaFile()
ENT.Type = "anim"
ENT.PrintName = "EZ Solid Fuel Generator"
ENT.Author = "Jackarunda, AdventureBoots"
ENT.Category = "JMod - EZ Machines"
ENT.Information = ""
ENT.Spawnable = true
ENT.Base = "ent_jack_gmod_ezmachine_base"
ENT.Model = "models/jmod/machines/biofuel_jenerator.mdl"
ENT.EZupgradable = true
--
ENT.JModPreferredCarryAngles = Angle(0, 0, 0)
ENT.Mass = 250
ENT.SpawnHeight = 5
--
ENT.StaticPerfSpecs = {
	MaxDurability = 100,
	MaxElectricity = 100,
	MaxWater = 100
}

ENT.DynamicPerfSpecs = {
	ChargeSpeed = 1,
	Armor = 1
}
ENT.EZconsumes = {
	JMod.EZ_RESOURCE_TYPES.BASICPARTS,
	JMod.EZ_RESOURCE_TYPES.COAL,
	JMod.EZ_RESOURCE_TYPES.WOOD,
	JMod.EZ_RESOURCE_TYPES.WATER
}
ENT.FlexFuels = { JMod.EZ_RESOURCE_TYPES.COAL, JMod.EZ_RESOURCE_TYPES.WOOD }

function ENT:CustomSetupDataTables()
	self:NetworkVar("Float", 2, "Progress")
	self:NetworkVar("Float", 3, "Water")
end

local STATE_BROKEN, STATE_OFF, STATE_ON = -1, 0, 1

if(SERVER)then
	function ENT:CustomInit()
		self:SetProgress(0)
		if self.SpawnFull then
			self:SetWater(self.MaxWater)
		else
			self:SetWater(0)
		end
		self.NextResourceThink = 0
		self.NextWaterLoseTime = 0
		self.NextUseTime = 0
		self.NextEffThink = 0
		self.NextFoofThink = 0
		self.NextEnvThink = 0
	end

	function ENT:Use(activator)
		if self.NextUseTime > CurTime() then return end
		local State = self:GetState()
		local alt = activator:KeyDown(JMod.Config.General.AltFunctionKey)
		JMod.SetEZowner(self, activator)
		JMod.Colorify(self)

		if State == STATE_BROKEN then
			JMod.Hint(activator, "destroyed", self)
			return
		elseif State == STATE_OFF then
			self:TurnOn(activator)
		elseif State == STATE_ON then
			if alt then
				self:ProduceResource()
				return
			end
			self:TurnOff()
		end
	end

	function ENT:TurnOn(activator)
		if self:GetState() > STATE_OFF then return end
		self:EmitSound("snd_jack_littleignite.wav")
		if (self:GetElectricity() > 0) and (self:GetWater() > 0) then
			self.NextUseTime = CurTime() + 1
			self:SetState(STATE_ON)
			timer.Simple(0.1, function()
				if(self.SoundLoop)then self.SoundLoop:Stop() end
				self.SoundLoop = CreateSound(self, "snds_jack_gmod/intense_fire_loop.wav")
				self.SoundLoop:SetSoundLevel(60)
				self.SoundLoop:Play()
			end)
		
		elseif self:GetElectricity() <= 0 then 
				JMod.Hint(activator, "need fuel")
		elseif self:GetWater() <= 0 then
				JMod.Hint(activator, "refill geo")
		end
			
	end

	function ENT:TurnOff()
		if (self:GetState() <= 0) then return end
		self.NextUseTime = CurTime() + 1
		if self.SoundLoop then self.SoundLoop:Stop() end
		--self:EmitSound("snds_jack_gmod/genny_stop.wav", 70, 100)
		self:EmitSound("snd_jack_littleignite.wav")
		self:ProduceResource()
		self:SetState(STATE_OFF)
	end

	function ENT:ResourceLoaded(typ, accepted)
		if (typ == JMod.EZ_RESOURCE_TYPES.COAL) or (typ == JMod.EZ_RESOURCE_TYPES.WOOD) and accepted > 0 then
			timer.Simple(.1, function() 
				if IsValid(self) then self:TurnOn() end 
			end)
		end
	end

	function ENT:OnRemove()
		if self.SoundLoop then self.SoundLoop:Stop() end
	end

	function ENT:ProduceResource()
		local SelfPos, Up, Forward, Right = self:GetPos(), self:GetUp(), self:GetForward(), self:GetRight()
		local amt = math.Clamp(math.floor(self:GetProgress()), 0, 100)

		if amt <= 0 then return end

		local pos = self:WorldToLocal(SelfPos + Up * 30 + Right * -40 + Forward * 60)
		JMod.MachineSpawnResource(self, JMod.EZ_RESOURCE_TYPES.POWER, amt, pos, Angle(0, 0, 0), Right * -60, true, 200)
		self:SetProgress(math.Clamp(self:GetProgress() - amt, 0, 100))
		--self:SpawnEffect(self:LocalToWorld(pos))
	end

	function ENT:OnBreak()
		if self.SoundLoop then
			self.SoundLoop:Stop()
		end
	end

	function ENT:ConsumeWater(amt)
		amt = (amt or .2)/(self.ElectricalEfficiency or 1)
		local NewAmt = math.Clamp(self:GetWater() - amt, 0.0, self.MaxWater)
		self:SetWater(NewAmt)
	end

	function ENT:Think()
		local Time, State, Grade = CurTime(), self:GetState(), self:GetGrade()
		local Up, Forward, Right = self:GetUp(), self:GetForward(), self:GetRight()

		if self.NextResourceThink < Time then
			self.NextResourceThink = Time + 1
			if State == STATE_ON then
				local NRGperFuel = 5.5
				local FuelToConsume = JMod.EZ_GRADE_BUFFS[Grade]
				local PowerToProduce = FuelToConsume * NRGperFuel
				local SpeedModifier = .2

				if self:GetWater() <= 0 or self:GetElectricity() <= 0 then
					self:TurnOff()
				end

				self:ConsumeElectricity(FuelToConsume * SpeedModifier)

				self:SetProgress(self:GetProgress() + PowerToProduce * SpeedModifier)

				self:ConsumeWater(FuelToConsume * 0.2 * SpeedModifier)

				if self:GetProgress() >= 100 then self:ProduceResource() end
			end
		end

		if (self.NextEffThink < Time) then
			self.NextEffThink = Time + .1
			if (State == STATE_ON) then
				local Eff = EffectData()
				Eff:SetOrigin(self:GetPos() + Up * 90 + Forward * 70)
				Eff:SetNormal(JMod.Wind:GetNormalized())
				Eff:SetScale(.1)
				util.Effect("eff_jack_gmod_ezoilfiresmoke", Eff, true)
				--
			end
		end
		if (self.NextFoofThink < Time) then
			self.NextFoofThink = Time + .3
			if (State == STATE_ON) then
				self:EmitSound("snds_jack_gmod/hiss.wav", 75, math.random(75, 80))
				local Foof = EffectData()
				Foof:SetOrigin(self:GetPos() + Up * 30 + Right * -25 + Forward * 35)
				Foof:SetNormal(-Right)
				Foof:SetScale(0.5)
				Foof:SetStart(self:GetPhysicsObject():GetVelocity())
				util.Effect("eff_jack_gmod_ezsteam", Foof, true, true)
			end
		end

		if (self.NextEnvThink < Time) then
			self.NextEnvThink = Time + 3
			if (State == STATE_ON) then
				local Tr = util.QuickTrace(self:GetPos() + Forward * 120, Vector(0, 0, 9e9), self)
				if not (Tr.HitSky) and (math.random(1, 3) == 1) then
					local Gas = ents.Create("ent_jack_gmod_ezgasparticle")
					Gas:SetPos(self:GetPos() + Forward * 120 + Vector(0, 0, 100))
					JMod.SetEZowner(Gas, self.EZowner)
					Gas:SetDTBool(0, true)
					Gas:Spawn()
					Gas:Activate()
					Gas.CurVel = (VectorRand() * math.random(1, 100))
				end
			end
		end
	end

	function ENT:PostEntityPaste(ply, ent, createdEntities)
		local Time = CurTime()
		JMod.SetEZowner(self, ply, true)
		ent.NextRefillTime = Time + math.Rand(0, 3)
		self.NextResourceThink = Time + math.Rand(0, 3)
		self.NextUseTime = Time + math.Rand(0, 3)
		self.NextEffThink = Time + math.Rand(0, 3)
		self.NextEnvThink = Time + math.Rand(0, 3)
		self.NextWaterLoseTime = Time
	end

	function ENT:OnDestroy(dmginfo)
		local Pos = self:GetPos()
		local Foof = EffectData()
		Foof:SetOrigin(Pos + self:GetUp() * 10)
		Foof:SetNormal(self:GetUp())
		Foof:SetScale(50)
		Foof:SetStart(self:GetPhysicsObject():GetVelocity())
		util.Effect("eff_jack_gmod_ezsteam", Foof, true, true)
		self:EmitSound("snds_jack_gmod/hiss.wav", 100, 100)

		local Range = 250
		for _, ent in pairs(ents.FindInSphere(Pos, Range)) do
			if ent ~= self then
				local DDistance = Pos:Distance(ent:GetPos())
				local DistanceFactor = (1 - DDistance / Range) ^ 2

				if JMod.ClearLoS(self, ent) then
					local Dmg = DamageInfo()
					Dmg:SetDamage(100 * DistanceFactor) -- wanna scale this with distance
					Dmg:SetDamageType(DMG_BURN)
					Dmg:SetDamageForce(Vector(0, 0, 5000) * DistanceFactor) -- some random upward force
					Dmg:SetAttacker((IsValid(dmginfo:GetAttacker()) and dmginfo:GetAttacker()) or game.GetWorld()) -- the earth is mad at you
					Dmg:SetInflictor(self or game.GetWorld())
					Dmg:SetDamagePosition(ent:GetPos())

					if ent.TakeDamageInfo then
						ent:TakeDamageInfo(Dmg)
					end
				end
			end
		end
	end

elseif(CLIENT)then
	function ENT:CustomInit()
		self:DrawShadow(true)
		self.Piston = JMod.MakeModel(self, "models/jmod/machines/biofuel_piston.mdl")
		self.Pusher = JMod.MakeModel(self, "models/jmod/machines/biofuel_pusher.mdl")
		self.Flywheel = JMod.MakeModel(self, "models/jmod/machines/biofuel_flywheel.mdl")
		self.WheelTurn = 0
		self.WheelMomentum = 0
	end

	local WhiteSquare = Material("white_square")
	local HeatWaveMat = Material("sprites/heatwave")

	function ENT:Draw()
		local SelfPos, SelfAng, State, FT = self:GetPos(), self:GetAngles(), self:GetState(), FrameTime()
		local Up, Right, Forward = SelfAng:Up(), SelfAng:Right(), SelfAng:Forward()
		local Grade = self:GetGrade()
		---
		--if State == STATE_ON then
			self.WheelMomentum = math.Clamp(self.WheelMomentum + FT / 3, 0, 0.4)
		--else
		--	self.WheelMomentum = math.Clamp(self.WheelMomentum - FT / 3, 0, 0.4)
		--end
		self.WheelTurn = self.WheelTurn - self.WheelMomentum*Grade*FT*300

		if self.WheelTurn > 360 then
			self.WheelTurn = 1
		elseif self.WheelTurn < 0 then
			self.WheelTurn = 360
		end
		local PistonCycle = math.sin((self.WheelTurn/360)*math.pi*2-math.pi+2)*16
		local InAndOut = math.sin((self.WheelTurn/360)*-math.pi*2-math.pi-0.7)*9
		---
		local BasePos = SelfPos
		local Obscured = util.TraceLine({start = EyePos(), endpos = BasePos, filter = {LocalPlayer(), self}, mask = MASK_OPAQUE}).Hit
		local Closeness = LocalPlayer():GetFOV() * (EyePos():Distance(SelfPos))
		local DetailDraw = Closeness < 120000 -- cutoff point is 400 units when the fov is 90 degrees
		---
		if((not(DetailDraw)) and (Obscured))then return end -- if player is far and sentry is obscured, draw nothing
		if(Obscured)then DetailDraw = false end -- if obscured, at least disable details
		if(State == STATE_BROKEN)then DetailDraw = false end -- look incomplete to indicate damage, save on gpu comp too
		---
		self:DrawModel()
		---
		if (State == STATE_ON) then
			local GlowPos = BasePos + Up * 60 + Forward * -13
			local GlowAng = SelfAng:GetCopy()
			GlowAng:RotateAroundAxis(GlowAng:Up(), 180)
			local GlowDir = GlowAng:Forward()
			render.SetMaterial(WhiteSquare)
			for i = 1, 5 do
				render.DrawQuadEasy(GlowPos + GlowDir * (1 + i / 5) * math.Rand(.9, 1), GlowDir, 24, 12, Color( 255, 255, 255, 200 ), GlowAng.r)
			end
			for i = 1, 20 do
				render.DrawQuadEasy(GlowPos + GlowDir * i / 2.5 * math.Rand(.9, 1), GlowDir, 24, 12, Color( 255 - i * 1, 255 - i * 9, 200 - i * 10, 55 - i * 2.5 ), GlowAng.r)
			end
			render.SetMaterial(HeatWaveMat)
			for i = 1, 2 do
				render.DrawSprite(BasePos + Up * (i * math.random(10, 30) + 80) + Forward * 70, 30, 30, Color(255, 255 - i * 10, 255 - i * 20, 25))
			end
			local light = DynamicLight(self:EntIndex())
			if (light) then
				light.Pos = GlowPos + Up * 1
				light.r = 255
				light.g = 200
				light.b = 100
				light.Brightness = 4
				light.Decay = 1000
				light.Size = 200 * math.Rand(.9, 1)
				light.DieTime = CurTime() + 0.1
			end
		end
		local PistonPos = BasePos + Up * 33.5 + Forward * 35.5 - Right * 22.8
		local PistonAng = SelfAng:GetCopy()
		--PistonCycle = 0
		PistonAng:RotateAroundAxis(Right, PistonCycle + -28)
		JMod.RenderModel(self.Piston, PistonPos, PistonAng, nil, Vector(1,1,1), JMod.EZ_GRADE_MATS[Grade])
		--InAndOut = 0
		local PusherPos = PistonPos + PistonAng:Forward() * (33 + InAndOut) - PistonAng:Right() * 0.4 + PistonAng:Up() * 0.1
		JMod.RenderModel(self.Pusher, PusherPos, PistonAng, nil, Vector(1,1,1), JMod.EZ_GRADE_MATS[Grade])
		local FlywheelPos = BasePos + Up * 18 + Forward * 64.5 - Right * 21.5
		local FlywheelAng = SelfAng:GetCopy()
		FlywheelAng:RotateAroundAxis(Right, self.WheelTurn)
		JMod.RenderModel(self.Flywheel, FlywheelPos, FlywheelAng, nil, Vector(1,1,1), JMod.EZ_GRADE_MATS[Grade])

		if DetailDraw then
			if Closeness < 20000 and State == STATE_ON then
				local DisplayAng = SelfAng:GetCopy()
				DisplayAng:RotateAroundAxis(DisplayAng:Right(), 0)
				DisplayAng:RotateAroundAxis(DisplayAng:Up(), -90)
				DisplayAng:RotateAroundAxis(DisplayAng:Forward(), 90)
				local Opacity = math.random(50, 150)
				local ProgFrac = self:GetProgress() / 100
				local FuelFrac = self:GetElectricity() / self.MaxElectricity
				local PresFrac = self:GetWater() / 100
				local R, G, B = JMod.GoodBadColor(ProgFrac)
				local PR, PG, PB = JMod.GoodBadColor(PresFrac)
				local FR, FG, FB = JMod.GoodBadColor(FuelFrac)

				cam.Start3D2D(SelfPos + Forward * -23 + Right * -16 + Up * 53, DisplayAng, .06)
				surface.SetDrawColor(10, 10, 10, Opacity + 50)
				local RankX, RankY = -70, 240
				surface.DrawRect(RankX, RankY, 128, 128)
				JMod.StandardRankDisplay(Grade, RankX + 62, RankY + 68, 118, Opacity + 50)
				draw.SimpleTextOutlined("PROGRESS", "JMod-Display", 0, 10, Color(255, 255, 255, Opacity), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 3, Color(0, 0, 0, Opacity))
				draw.SimpleTextOutlined(tostring(math.Round(ProgFrac * 100)) .. "%", "JMod-Display", 0, 40, Color(R, G, B, Opacity), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 3, Color(0, 0, 0, Opacity))
				draw.SimpleTextOutlined("WATER", "JMod-Display", 0, 80, Color(255, 255, 255, Opacity), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 3, Color(0, 0, 0, Opacity))
				draw.SimpleTextOutlined(tostring(math.Round(PresFrac * 100)) .. "%", "JMod-Display", 0, 110, Color(PR, PG, PB, Opacity), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 3, Color(0, 0, 0, Opacity))
				draw.SimpleTextOutlined("FUEL", "JMod-Display", 0, 150, Color(255, 255, 255, Opacity), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 3, Color(0, 0, 0, Opacity))
				draw.SimpleTextOutlined(tostring(math.Round(FuelFrac * 100)) .. "%", "JMod-Display", 0, 180, Color(FR, FG, FB, Opacity), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 3, Color(0, 0, 0, Opacity))
				cam.End3D2D()
			end
		end
	end
	language.Add("ent_jack_gmod_ezsfg", "EZ Solid Fuel Generator")
end