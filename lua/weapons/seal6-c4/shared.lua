AddCSLuaFile("shared.lua")

SWEP.Author			= "Hoff"
SWEP.Instructions	= "Left click to detonate placed C4s that produce ACF explosions.\nRight click to throw a C4.\nPress R to pick up your placed C4."

SWEP.Category			= "CoD Multiplayer"
SWEP.Spawnable			= true
SWEP.AdminSpawnable		= true

SWEP.ViewModel			= "models/hoff/weapons/c4/c_c4.mdl"
SWEP.WorldModel			= "models/hoff/weapons/c4/w_c4.mdl"
SWEP.ViewModelFOV		= 75
SWEP.UseHands			= true

SWEP.Primary.ClipSize		= -1
SWEP.Primary.DefaultClip	= 5
SWEP.Primary.Automatic		= true
SWEP.Primary.Ammo			= "slam"
SWEP.Primary.Delay			= 0.45

SWEP.Secondary.ClipSize		= -1
SWEP.Secondary.DefaultClip	= -1
SWEP.Secondary.Automatic	= true
SWEP.Secondary.Ammo			= "none"

SWEP.Weight				= 5
SWEP.AutoSwitchTo		= false
SWEP.AutoSwitchFrom		= false

SWEP.PrintName			= "C4"
SWEP.Slot				= 4
SWEP.SlotPos			= 1
SWEP.DrawAmmo			= true
SWEP.DrawCrosshair		= true

SWEP.Offset = {
	Pos = {
		Up = 0,
		Right = 7,
		Forward = 3.5,
	},
	Ang = {
		Up = 0,
		Right = 90,
		Forward = 190,
	}
}

local cvarFlags = { FCVAR_REPLICATED, FCVAR_ARCHIVE }
local throwSpeedCvar = CreateConVar("C4_ThrowSpeed", 1, cvarFlags, "How long is the delay between C4 throws?", 0.1, 10)
local infiniteCvar = CreateConVar("C4_Infinite", 0, cvarFlags, "Should C4 be infinite? 1 = infinite", 0, 1)
local maxCountCvar = CreateConVar("C4_MaxCount", "10", cvarFlags, "The maximum number of C4 that can be deployed at once.")

function SWEP:DrawWorldModel()
	local owner = self:GetOwner()

	if not IsValid(owner) then
		self:DrawModel()
		return
	end

	local bone = owner:LookupBone("ValveBiped.Bip01_R_Hand")
	if not bone then
		self:DrawModel()
		return
	end

	local pos, ang = owner:GetBonePosition(bone)
	local right, forward, up = ang:Right(), ang:Forward(), ang:Up()
	local offset = self.Offset
	pos = pos + right * offset.Pos.Right + forward * offset.Pos.Forward + up * offset.Pos.Up
	ang:RotateAroundAxis(right, offset.Ang.Right)
	ang:RotateAroundAxis(forward, offset.Ang.Forward)
	ang:RotateAroundAxis(up, offset.Ang.Up)

	self:SetRenderOrigin(pos)
	self:SetRenderAngles(ang)

	self:DrawModel()
end

function SWEP:Initialize()
	-- something keeps setting deploy speed to 4, this is a workaround
	self:SetDeploySpeed(1)
end

function SWEP:Deploy()
	-- something keeps setting deploy speed to 4, this is a workaround
	self:SetDeploySpeed(1)

	local owner = self:GetOwner()

	if not owner.C4s or #owner.C4s == 0 then
		owner.C4s = {}
	end

	timer.Simple(0.3, function()
		if IsValid(self) then
			self:EmitSound("hoff/mpl/seal_c4/bar_selectorswitch.wav", 45)
		end
	end)

	self:SetCollisionGroup(COLLISION_GROUP_NONE)
	self:SetHoldType("Slam")

	return true
end

function SWEP:StartExplosionChain()
	local c4s = self:GetOwner().C4s
	if #c4s <= 0 then return end

	local ent = c4s[1] -- Get the first entity in the table

	if not IsValid(ent) then
		table.remove(c4s, 1)
		self:StartExplosionChain()
		return
	end

	if ent.QueuedForExplode then
		return
	end

	ent.QueuedForExplode = true
	ent.ExplodedViaWorld = false
	ent:DelayedDestroy(true)
end

function SWEP:PrimaryAttack()
	self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)

	timer.Simple(0.1, function()
		if IsValid(self) then
			self:EmitSound("hoff/mpl/seal_c4/c4_click.wav")
		end
	end)

	if SERVER and self:GetOwner():Alive() and self:GetOwner():IsValid() then
		timer.Simple(0.175, function()
			if IsValid(self) then
				self:StartExplosionChain()
			end
		end)
	end

	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)

	-- Need to stop insane values from crashing servers
	local ClampedThrowSpeed = math.Clamp(throwSpeedCvar:GetFloat(), 0.25, 10)
	self:SetNextSecondaryFire(CurTime() + (0.8 / ClampedThrowSpeed))
end

hook.Add("PlayerDeath", "SetAllC4sUnowned", function(victim)
	if IsValid(victim) and victim:IsPlayer() and victim.C4s and #victim.C4s > 0 then
		for k in pairs(victim.C4s) do
			victim.C4s[k].ExplodedViaWorld = true
		end
	end
end)

function SWEP:SecondaryAttack()
	local isInfinite = infiniteCvar:GetBool()
	if not isInfinite and self:Ammo1() <= 0 then return end

	local owner = self:GetOwner()
	if owner:GetCount("black_ops_c4s") >= maxCountCvar:GetInt() then return end

	self:SendWeaponAnim(ACT_VM_THROW)
	owner:SetAnimation(PLAYER_ATTACK1)
	self:EmitSound("hoff/mpl/seal_c4/whoosh_01.wav")

	timer.Simple(0.095, function()
		if not IsValid(self) or not IsValid(owner) then return end

		if SERVER then
			local TargetPosition = owner:GetShootPos() + (owner:GetRight() * -8) + (owner:GetUp() * -1) + (owner:GetForward() * 10)

			local model = "models/hoff/weapons/c4/w_c4.mdl"
			util.PrecacheModel(model)

			local TempC4 = ents.Create("prop_physics")
			TempC4:SetModel(model)
			TempC4:SetPos(TargetPosition)
			TempC4:SetCollisionGroup(COLLISION_GROUP_NONE)
			TempC4:Spawn()

			local mins, maxs = TempC4:GetCollisionBounds()

			TempC4:Remove()

			-- Use the mins and maxs vectors to check if there is enough space to spawn another c4
			local tr = util.TraceHull({start = TargetPosition, endpos = TargetPosition, mins = mins, maxs = maxs, mask = MASK_BLOCKLOS})

			-- Check if the trace hit something
			if not owner:IsLineOfSightClear(TargetPosition) or tr.Hit then
				TargetPosition = owner:EyePos()
			end

			local ent = ents.Create("cod-c4")
			ent:SetPos(vector_origin)
			ent:SetOwner(owner)  -- Disables collision between the C4 and its owner
			ent:SetPos(TargetPosition)
			ent:SetAngles(Angle(1, 0, 0))
			ent:Spawn()
			ent.C4Owner = owner
			ent.ThisTrigger = self
			ent.ExplodedViaWorld = false
			ent.QueuedForExplode = false
			ent.UniqueExplodeTimer = "ExplodeTimer" .. owner:SteamID() .. math.Rand(1, 1000)
			ent:SetNWString("OwnerID", owner:SteamID())

			local phys = ent:GetPhysicsObject()

			--phys:SetMass(0.6)

			-- Compensate for the offcenter spawn
			local aimvector = owner:GetAimVector()
			local aimangle = aimvector:Angle()
			aimangle:RotateAroundAxis(aimangle:Up(), -1.5)
			aimvector = aimangle:Forward()
			phys:ApplyForceCenter(aimvector * 1500)

			-- The positive z coordinate emulates the spin from a left underhand throw
			local angvel = Vector(0, math.random(-5000, -2000), math.random(-100, -900))
			angvel:Rotate(-1 * ent:EyeAngles())
			angvel:Rotate(Angle(0, owner:EyeAngles().y, 0))

			angvel.x = math.Clamp(angvel.x, -1000, 1000)
			angvel.y = math.Clamp(angvel.y, -1000, 1000)
			angvel.z = math.Clamp(angvel.z, -1000, 1000)

			phys:SetAngleVelocity(angvel)

			table.insert(owner.C4s, ent)

			if engine.ActiveGamemode() ~= "nzombies" then
				undo.Create("C4")
					undo.AddEntity(ent)
					undo.SetPlayer(owner)
					undo.AddFunction(function(UndoFunc)
						local UndoEnt = UndoFunc.Entities[1]

						-- Check if the entity is still valid
						if UndoEnt:IsValid() then
							-- Remove the entity from the owner's C4s table
							table.RemoveByValue(UndoFunc.Owner.C4s, ent)
						else
							-- The c4 doesn't exist anymore (probably exploded)
							return false
						end
					end)
				undo.Finish()

				owner:AddCount("sents", ent) -- Add to the SENTs count ( ownership )
				owner:AddCount("black_ops_c4s", ent) -- Add count to our personal count
				owner:AddCleanup("sents", ent) -- Add item to the sents cleanup
				owner:AddCleanup("black_ops_c4s", ent) -- Add item to the cleanup
			end
		end

		if not isInfinite then
			owner:RemoveAmmo(1, "slam")
		end
	end)

	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)

	-- Need to stop insane values from crashing servers
	local ClampedThrowSpeed = math.Clamp(throwSpeedCvar:GetFloat(), 0.25, 10)
	self:SetNextSecondaryFire(CurTime() + (0.8 / ClampedThrowSpeed))
end

function SWEP:ShouldDropOnDie()
	return false
end

function SWEP:Reload()
	-- First, check if the reload delay has expired
	if self.ReloadDelay and CurTime() < self.ReloadDelay then
		return
	end

	-- Trace a line to a hit location and do a sphere trace from there and sort by distance
	-- We have to do this because GetEyeTrace to a c4 parented to an entity is unreliable
	local owner = self:GetOwner()
	local eyePos = owner:EyePos()
	local trace = util.TraceLine({
		start = eyePos,
		endpos = eyePos + owner:EyeAngles():Forward() * 85,
		filter = {owner}
	})
	local hitPos = trace.HitPos
	local c4s = ents.FindInSphere(hitPos, 1)
	table.sort(c4s, function(a, b) return a:GetPos():Distance(hitPos) < b:GetPos():Distance(hitPos) end)
	local hitEnt = nil

	for _, ent in ipairs(c4s) do
		if ent:GetClass() == "cod-c4" then
			hitEnt = ent
			break
		end
	end

	-- Check if the trace hit an entity and if it is a C4 entity
	if not IsValid(hitEnt) or hitEnt:GetClass() ~= "cod-c4"then return end
	if hitEnt:GetNWString("OwnerID") ~= owner:SteamID() then return end

	local entPos = hitEnt:GetPos()
	if eyePos:Distance(entPos) > 85 then return end

	local effectData = EffectData()
	effectData:SetOrigin(entPos)
	util.Effect("inflator_magic", effectData)

	if SERVER then
		if infiniteCvar:GetBool() == false then
			-- Give the player one "Slam" ammo
			owner:GiveAmmo(1, "Slam")
		end

		-- Remove the C4 entity from the player's C4s array
		if table.HasValue(owner.C4s, hitEnt) then
			table.RemoveByValue(owner.C4s, hitEnt)
		end

		-- Remove the C4 entity from the world
		hitEnt:Remove()
	elseif CLIENT and VManip then
		VManip:PlayAnim("interactslower")
	end

	-- Set the reload delay so the player cannot reload again for 0.5 seconds
	self.ReloadDelay = CurTime() + 0.5
end

local crosshairMat = Material("models/hoff/weapons/c4/c4_reticle.png")

function SWEP:DoDrawCrosshair(x, y)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(crosshairMat)
	surface.DrawTexturedRect(x - 16, y - 16, 32, 32)
	return true
end