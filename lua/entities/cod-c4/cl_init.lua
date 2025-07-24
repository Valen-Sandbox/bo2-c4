include("shared.lua")

ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

local lightCvar = GetConVar("C4_RedLight")
local lightMat = Material("sprites/glow04_noz")
local lightColor = Color(237, 72, 65, 255)
local textFont = "TargetID"

function ENT:Draw()
	self:DrawShadow(false)
	self:DrawModel()

	if C4Flash and lightCvar:GetBool() == true then
		local pos = self:GetPos() + self:GetUp() * 4.3 + self:GetForward() * -2.75 -- Position of the sprite
		local size = 15 -- Size of the sprite

		render.SetMaterial(lightMat)
		render.DrawSprite(pos, size, size, lightColor)
	end
end

function ENT:Initialize()
	if not timer.Exists("C4FlashTimer") then
		C4Flash = false
		timer.Create("C4FlashTimer", 1, 0, function()
			C4Flash = true
			timer.Simple(0.1, function()
				C4Flash = false
			end)
		end)
	end

	-- Always use the VManip animation from Manual Pickup
	-- https://steamcommunity.com/sharedfiles/filedetails/?id=2156004721
	if CLIENT and VManip and not VManip:GetAnim("interactslower") then
		VManip:RegisterAnim("interactslower", {
			["model"] = "c_vmanipinteract.mdl",
			["lerp_peak"] = 0.7,
			["lerp_speed_in"] = 1,
			["lerp_speed_out"] = 0.8,
			["lerp_curve"] = 2.5,
			["speed"] = 1,
			["startcycle"] = 0,
			["sounds"] = {},
			["loop"] = false
		})
	end
end

hook.Add("HUDPaint", "C4HudText",function()
	local locPly = LocalPlayer()
	local visibleEnt = locPly:GetEyeTrace().Entity
	if not IsValid(visibleEnt) or not locPly:Alive() then return end
	if visibleEnt:GetClass() ~= "cod-c4" then return end

	local eyePos = locPly:EyePos()
	local player_to_entity_distance = eyePos:Distance(visibleEnt:GetPos())

	if player_to_entity_distance >= 85 then return end
	if visibleEnt:GetNWString("OwnerID") ~= locPly:SteamID() then return end
	if locPly:GetActiveWeapon():GetClass() ~= "seal6-c4" then return end
	if not visibleEnt:GetNWBool("Hit") then return end

	local textX = ScrW() / 2
	local textY = ScrH() / 2 + 200
	local useKey = input.LookupBinding("+reload") or "R" -- fallback to "R" if not bound
	draw.DrawText("Press " .. string.upper(useKey) .. " to Pick Up C4", textFont, textX, textY, color_white, TEXT_ALIGN_CENTER)
end)