-- Demo: the stream player is a gunslinger in Dusty Gulch.
local function F() return RDR.Wdir(1, 0) end   -- down the street
local function R() return RDR.Wdir(0, -1) end  -- to the host's right

local function toStreet(dx)
	local h = Sigf.Host()
	if not IsValid(h) then return end
	local p = RDR.W(dx or -400, -90, 10)
	Sigf.Teleport(h, p, Vector(0, 0, 0))
	h:SetEyeAngles(Angle(0, RDR.yaw or 0, 0))
end

local function foes(n, kind, dist)
	local h = Sigf.Host()
	for i = 1, n do
		local e = (kind == "law") and RDR.SpawnLaw() or RDR.SpawnOutlaw(false)
		if IsValid(e) and IsValid(h) then
			local f = h:GetPos() + F() * ((dist or 380) + i * 40) + R() * ((i - (n + 1) / 2) * 90)
			Sigf.Teleport(e, Vector(f.x, f.y, h:GetPos().z + 8), Vector(0, 0, 0))
			e:SetAngles(Angle(0, (RDR.yaw or 0) + 180, 0))
		end
	end
end

Sigf.Demo(0.3, function()
	RDR.holdBoss = true
	toStreet(-500)
	Sigf.Give("weapon_357")
	local h = Sigf.Host()
	if IsValid(h) then h:GiveAmmo(200, "357", true) end
	Sigf.Text("RED DEAD x GARRY'S MOD", 4, { y = 0.2 })
	RDR.Net("title", { text = "DUSTY GULCH", sub = "Chapter 1: Outlaws for Life" })
end)
Sigf.Demo(4, function() Sigf.Text("Welcome to Dusty Gulch: outlaws vs the law", 5, { y = 0.2, size = 44 }) foes(2, "outlaw", 450) end)
Sigf.Demo(13, function()
	RDR.deCool = 0
	Sigf.Pilot(false)
	foes(3, "law", 500)
	foes(1, "outlaw", 520)
	Sigf.Text("DEAD EYE: time slows, paint your targets", 5, { y = 0.2, size = 44 })
	Sigf.After(0.8, function() RDR.DeadEye(Sigf.Host()) end)
	Sigf.After(5, function() Sigf.Pilot(true) end)
end)
Sigf.Demo(27, function()
	Sigf.Text("A bounty appears: WANTED dead or alive", 5, { y = 0.2, size = 44 })
	RDR.holdBoss = false
	RDR.bossCooldown = 0
	Sigf.After(1.5, function()
		local b = RDR.Boss
		local h = Sigf.Host()
		if IsValid(b) and IsValid(h) then
			local f = h:GetPos() + F() * 420
			Sigf.Teleport(b, Vector(f.x, f.y, h:GetPos().z + 8), Vector(0, 0, 0))
		end
	end)
end)
Sigf.Demo(37, function()
	local b = RDR.Boss
	if IsValid(b) then
		Sigf.Pilot(false)
		Sigf.LookAt(b, 3.5)
		Sigf.Shoot(3.5)
		Sigf.After(3.2, function() if IsValid(b) then Sigf.KillByHost(b) end Sigf.Pilot(true) end)
	end
end)
Sigf.Demo(44, function()
	RDR.holdBoss = true
	Sigf.Pilot(false)
	local h = Sigf.Host()
	if not IsValid(h) then return end
	h:SetEyeAngles(Angle(0, RDR.yaw or 0, 0))
	Sigf.Text("Shoot the TNT barrels!", 4, { y = 0.2, size = 44 })
	local p = h:GetPos() + F() * 380
	local barrels = {}
	for i = -1, 1 do
		barrels[#barrels + 1] = Sigf.Prop("models/props_c17/oildrum001_explosive.mdl", p + R() * (i * 70) + Vector(0, 0, 10), 1, 15)
	end
	foes(3, "outlaw", 330)
	RDR.Cam(h:GetPos() + F() * 200 - R() * 200 + Vector(0, 0, 80), p + F() * 80 + Vector(0, 0, 40), 4.5)
	Sigf.After(1.2, function() Sigf.LookAt(Vector(p.x, p.y, p.z + 20), 2) Sigf.Shoot(1.5) end)
	Sigf.After(2.6, function()
		for _, b in ipairs(barrels) do if IsValid(b) then b:TakeDamage(60, h, h) end end
	end)
	Sigf.After(4.5, function() Sigf.Pilot(true) end)
end)
Sigf.Demo(56, function()
	Sigf.Pilot(false)
	local h = Sigf.Host()
	if not IsValid(h) then return end
	h:SetEyeAngles(Angle(0, RDR.yaw or 0, 0))
	foes(4, "outlaw", 330)
	Sigf.Text("STAMPEDE! Horse statues are physics props", 4, { y = 0.2, size = 44 })
	local f = h:GetPos() + F() * 1000
	RDR.Stampede(Vector(f.x, f.y, h:GetPos().z + 70), -F())
	local hp = h:GetPos()
	RDR.Cam(hp + F() * 700 - R() * 230 + Vector(0, 0, 90), hp + F() * 150 + Vector(0, 0, 50), 4.5)
	Sigf.After(5, function() Sigf.Pilot(true) end)
end)
Sigf.Demo(66, function()
	RDR.deCool = 0
	foes(3, "outlaw", 420)
	Sigf.Text("RED DEAD x GARRY'S MOD", 4)
	Sigf.After(0.5, function() RDR.DeadEye(Sigf.Host()) end)
end)
