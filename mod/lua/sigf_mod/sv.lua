-- Red Dead Redemption 2 Takeover: the arena becomes the frontier town of Dusty Gulch.
-- Outlaws fight deputies, the wanted board fills with bounties, Dead Eye slows time and paints targets.
RDR = RDR or { cash = 0, honor = 60, town = {}, kills = 0 }
local U = 47.5 -- one Hunter block unit

-- town frame: C is the street center, RDR.yaw turns the whole town (so the street faces open ground)
local function rot(x, y)
	local r = math.rad(RDR.yaw or 0)
	return x * math.cos(r) - y * math.sin(r), x * math.sin(r) + y * math.cos(r)
end
local function W(x, y, z)
	local rx, ry = rot(x, y)
	return RDR.C + Vector(rx, ry, z)
end
RDR.W = W
local function Wdir(x, y)
	local rx, ry = rot(x, y)
	return Vector(rx, ry, 0)
end
RDR.Wdir = Wdir

for _, n in ipairs({ "rdr_msg" }) do util.AddNetworkString(n) end

local function net2(kind, data)
	net.Start("rdr_msg")
	net.WriteString(kind)
	net.WriteTable(data or {})
	net.Broadcast()
end
RDR.Net = net2

-- camera cut for the demo: look at `look` from `pos` for `sec` seconds
function RDR.Cam(pos, look, sec)
	SetGlobalVector("rdr_cam_pos", pos)
	SetGlobalVector("rdr_cam_look", look)
	SetGlobalFloat("rdr_cam_until", CurTime() + sec)
end

Sigf.Battle.enabled = false
if Sigf.IsDemo() then RDR.holdBoss = true end

local OUTLAW_NAMES = { "Arthur Mud", "Dutch van der Lard", "Mikey Bell", "John Marstoon", "Sadie Alder", "Javier Esquire", "Bill Bulldoze", "Lenny Sumner", "Charles Smythe", "Hosea Mathews", "Karen Gunn", "Uncle Dusty" }
local LAW_NAMES = { "Deputy Dave", "Marshal Pike", "Agent Milton", "Agent Ross", "Deputy Fitch", "Sheriff Gray", "Deputy Moe" }
local CHAPTERS = { "The Beans Run Out", "Horses Are Not Cars", "One Last Job (Again)", "Dutch Has a Plan", "Honor Among Tumbleweeds", "Redemption, Mostly" }
local BOSS_NAMES = { "Dutch van der Lard", "Micah Belle", "Colm O'Dribble", "Leviticus Crumb", "Angelo Bronkoo" }

local function mkProp(model, pos, ang, mat, col, frozen)
	if not util.IsValidModel(model) then Sigf.Report("rdr", "missing model " .. model) return nil end
	local e = ents.Create("prop_physics")
	e:SetModel(model)
	e:SetPos(pos)
	e:SetAngles(ang or angle_zero)
	e:Spawn()
	if mat then e:SetMaterial(mat) end
	if col then e:SetColor(col) end
	local ph = e:GetPhysicsObject()
	if IsValid(ph) and frozen ~= false then ph:EnableMotion(false) e:SetNW2Bool("rdr_town", true) end
	return e
end

---------------------------------------------------------------- town construction
-- A panel is placed so its longest side runs along dir, its middle side is vertical, its thin side is the thickness.
local function panel(model, center, dir)
	local e = mkProp(model, center + Vector(0, 0, 4000), angle_zero, "sigf/planks", nil, false)
	if not e then return end
	local mn, mx = e:OBBMins(), e:OBBMaxs()
	local sz = { mx.x - mn.x, mx.y - mn.y, mx.z - mn.z }
	local idx = { 1, 2, 3 }
	table.sort(idx, function(a, b) return sz[a] > sz[b] end)
	local long, mid, thin = idx[1], idx[2], idx[3]
	local D = Vector(dir.x, dir.y, 0) D:Normalize()
	local Z = Vector(0, 0, 1)
	local N = D:Cross(Z)
	local v = {}
	v[long], v[mid], v[thin] = D, Z, N
	-- right-handed basis: left (local y) = up x forward; flip the thin axis when it is not
	if v[3]:Cross(v[1]):Dot(v[2]) < 0 then v[thin] = -v[thin] end
	e:SetAngles(v[1]:AngleEx(v[3]))
	e:SetPos(e:GetPos() + (center - e:WorldSpaceCenter()))
	local ph = e:GetPhysicsObject()
	if IsValid(ph) then ph:EnableMotion(false) end
	e:SetNW2Bool("rdr_town", true)
	RDR.town[#RDR.town + 1] = e
	return e
end

-- Flat plate (street, roof): long side along X (wantX) or Y.
local function plate(model, center, wantX, mat, col)
	local e = mkProp(model, center, angle_zero, mat or "sigf/planks", col)
	if not e then return end
	local mn, mx = e:OBBMins(), e:OBBMaxs()
	local sx, sy = mx.x - mn.x, mx.y - mn.y
	e:SetAngles(Angle(0, ((sx > sy) ~= wantX and 90 or 0) + (RDR.yaw or 0), 0))
	e:SetPos(e:GetPos() + (center - e:WorldSpaceCenter()))
	RDR.town[#RDR.town + 1] = e
	return e
end

local function addTown(e) if e then RDR.town[#RDR.town + 1] = e end return e end

local function sign(pos, ang, text, size, col)
	local e = ents.Create("prop_dynamic")
	e:SetModel("models/hunter/blocks/cube025x025x025.mdl")
	e:SetPos(pos)
	e:Spawn()
	e:SetRenderMode(RENDERMODE_TRANSCOLOR)
	e:SetColor(Color(255, 255, 255, 0))
	e:SetNotSolid(true)
	e:DrawShadow(false)
	e:SetNW2String("rdr_st", text)
	e:SetNW2Angle("rdr_sa", Angle(ang.p, ang.y + (RDR.yaw or 0), ang.r))
	e:SetNW2Int("rdr_ss", size or 60)
	e:SetNW2Vector("rdr_sc", Vector(col and col.r or 240, col and col.g or 220, col and col.b or 170))
	RDR.town[#RDR.town + 1] = e
end

-- side = +1 (north row, faces south) or -1. xc = x offset along the street. w, d in block units.
local function building(C, side, xc, w, d, name, tint)
	local tiers = 2
	local H = 2 * U
	local face = -side -- the front faces the street
	local ym = side * (260 + d * U * 0.5) -- center line of the building
	local yf = side * 260 -- street-side front line
	local yb = side * (260 + d * U)
	local X = Wdir(1, 0)
	local Y = Wdir(0, 1)
	local wsz = w * U
	-- front wall: door gap of 2 units in the middle on the ground tier
	local a = (w - 2) / 2
	for t = 0, tiers - 1 do
		local z = H * (t + 0.5)
		if t == 0 then
			local pm = "models/hunter/blocks/cube2x" .. a .. "x025.mdl"
			panel(pm, W(xc - (1 + a / 2) * U, yf, z), X)
			panel(pm, W(xc + (1 + a / 2) * U, yf, z), X)
		else
			panel("models/hunter/blocks/cube2x" .. w .. "x025.mdl", W(xc, yf, z), X)
		end
		panel("models/hunter/blocks/cube2x" .. w .. "x025.mdl", W(xc, yb, z), X)
		panel("models/hunter/blocks/cube2x" .. d .. "x025.mdl", W(xc - wsz / 2, ym, z), Y)
		panel("models/hunter/blocks/cube2x" .. d .. "x025.mdl", W(xc + wsz / 2, ym, z), Y)
	end
	-- roof and false front
	local rm = "models/hunter/plates/plate" .. math.max(w, d) .. "x" .. math.min(w, d) .. ".mdl"
	if not util.IsValidModel(rm) then rm = "models/hunter/plates/plate" .. math.min(w, d) .. "x" .. math.max(w, d) .. ".mdl" end
	plate(rm, W(xc, ym, H * tiers + 2), w >= d, "sigf/planks", tint)
	local ff = panel("models/hunter/blocks/cube2x" .. w .. "x025.mdl", W(xc, yf, H * tiers + U), X)
	if ff then ff:SetColor(tint or color_white) end
	-- porch roof over the boardwalk
	plate("models/hunter/plates/plate1x" .. w .. ".mdl", W(xc, yf + face * U * 0.6, H + 4), true, "sigf/planks", tint)
	-- sign above the porch
	sign(W(xc, yf + face * 10, H * tiers + U), Angle(0, (face > 0 and 90 or -90) - 90, 90), name, 52 + (w - 6) * 3)
end

local function buildTown(C)
	-- dusty street: big plates with the dirt skin
	for i = -1, 0 do
		plate("models/hunter/plates/plate24x32.mdl", W(i * 24 * U + 12 * U, 0, 1), false, "sigf/dirt", Color(175, 150, 125))
	end
	building(C, 1, -700, 8, 6, "SALOON", Color(205, 130, 90))
	building(C, 1, -50, 6, 6, "SHERIFF", Color(150, 160, 200))
	building(C, 1, 580, 8, 6, "GENERAL STORE", Color(190, 170, 110))
	building(C, -1, -650, 6, 6, "BANK", Color(160, 185, 160))
	building(C, -1, 0, 8, 6, "UNDERTAKER", Color(170, 140, 170))
	building(C, -1, 650, 6, 6, "HOTEL", Color(200, 180, 140))
	-- town entrance sign
	sign(W(-1250, 0, 150), Angle(0, -90, 90), "DUSTY GULCH", 80)
	RDR.Decor(C)
end

function RDR.Decor(C)
	local function prop(model, p, a, sc, col)
		local e = mkProp(model, p, a or Angle(0, math.random(360), 0), nil, col)
		if e and sc then e:SetModelScale(sc, 0) end
		addTown(e)
		return e
	end
	prop("models/props_c17/statue_horse.mdl", W(-1000, -150, 0), Angle(0, 20 + (RDR.yaw or 0), 0), 0.8)
	prop("models/props_lab/cactus.mdl", W(-1100, 200, 0), nil, 2.2)
	prop("models/props_lab/cactus.mdl", W(1050, -300, 0), nil, 2.6)
	prop("models/props_lab/cactus.mdl", W(900, 330, 0), nil, 1.8)
	for i = 1, 6 do
		prop("models/props_c17/gravestone00" .. (i % 4 + 1) .. "a.mdl", W(-500 + i * 90, 1000 + (i % 2) * 70, 0), Angle(0, 180, 0))
	end
	prop("models/props_c17/gravestone_cross001a.mdl", W(100, 1060, 0), Angle(0, 180, 0))
	for i = -2, 2 do
		prop("models/props_c17/fence03a.mdl", W(i * 100 + 1200, 150, 0), Angle(0, 90, 0))
	end
	prop("models/props_c17/oildrum001_explosive.mdl", W(250, -200, 0))
	prop("models/props_c17/oildrum001_explosive.mdl", W(270, -170, 0))
	prop("models/props_c17/oildrum001_explosive.mdl", W(-120, 205, 0))
	prop("models/props_junk/wood_crate001a.mdl", W(380, 215, 0))
	prop("models/props_junk/wood_crate001a.mdl", W(380, 215, 40))
	prop("models/props_junk/wood_crate002a.mdl", W(-20, -205, 0))
	prop("models/props_junk/pushcart01a.mdl", W(520, -190, 0))
	prop("models/props_c17/lamppost03a_off.mdl", W(-1150, -230, 0))
end

---------------------------------------------------------------- cowboy hats
local function makeHat(kind, col)
	local brimM, crownM, bs, cs, cz
	local brim = mkProp("models/hunter/tubes/circle2x2.mdl", Vector(0, 0, 3000), angle_zero, "models/debug/debugwhite", col, false)
	local crown = mkProp("models/hunter/misc/sphere075x075.mdl", Vector(0, 0, 3100), angle_zero, "models/debug/debugwhite", col, false)
	if not (brim and crown) then return end
	if kind == "law" then
		brim:SetModelScale(0.3, 0) crown:SetModelScale(0.42, 0)
	else
		brim:SetModelScale(0.3, 0) crown:SetModelScale(0.5, 0)
	end
	for _, e in ipairs({ brim, crown }) do
		e:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
		e:SetRenderMode(RENDERMODE_NORMAL)
	end
	crown:SetColor(Color(col.r * 0.8, col.g * 0.8, col.b * 0.8))
	return brim, crown
end

local function wearHat(npc, kind, col)
	local brim, crown = makeHat(kind, col)
	if not brim then return end
	local att = npc:LookupAttachment("eyes")
	brim:SetParent(npc, att)
	brim:SetLocalPos(Vector(-2, 0, 6.5))
	brim:SetLocalAngles(Angle(0, 0, 0))
	crown:SetParent(brim)
	crown:SetLocalPos(Vector(0, 0, 1))
	crown:SetLocalAngles(angle_zero)
	npc.RDRHat = brim
	npc.RDRHatCrown = crown
end

local function dropHat(npc)
	local h = npc.RDRHat
	if not IsValid(h) then return end
	local pos, ang, col = h:GetPos(), h:GetAngles(), h:GetColor()
	local kind = npc:GetNW2String("rdr_team", "") == "law" and "law" or "outlaw"
	-- a new hat flies off the head (created next tick: not allowed inside a physics callback)
	timer.Simple(0, function()
		local brim, crown = makeHat(kind, Color(col.r, col.g, col.b))
		if not brim then return end
		brim:SetPos(pos)
		brim:SetAngles(ang)
		crown:SetParent(brim)
		crown:SetLocalPos(Vector(0, 0, 1))
		crown:SetLocalAngles(angle_zero)
		brim:PhysicsInit(SOLID_VPHYSICS)
		brim:SetMoveType(MOVETYPE_VPHYSICS)
		brim:SetSolid(SOLID_VPHYSICS)
		local ph = brim:GetPhysicsObject()
		if IsValid(ph) then
			ph:Wake()
			ph:SetVelocity(Vector(math.Rand(-80, 80), math.Rand(-80, 80), 260))
			ph:AddAngleVelocity(Vector(math.Rand(-300, 300), math.Rand(-300, 300), math.Rand(-300, 300)))
		end
		SafeRemoveEntityDelayed(brim, 12)
	end)
end

hook.Add("PlayerSpawn", "rdr_player_hat", function(ply)
	timer.Simple(0.6, function()
		if not IsValid(ply) or IsValid(ply.RDRHat) or ply.RDRHatBusy then return end
		ply.RDRHatBusy = true
		if Sigf.IsCamera and Sigf.IsCamera(ply) then return end
		local brim, crown = makeHat("outlaw", Color(120, 80, 45))
		if not brim then return end
		local bone = ply:LookupBone("ValveBiped.Bip01_Head1")
		if bone then
			brim:FollowBone(ply, bone)
			brim:SetLocalPos(Vector(4, -3, 0))
			brim:SetLocalAngles(Angle(0, -90, -90))
		else
			brim:SetParent(ply)
		end
		crown:SetParent(brim)
		crown:SetLocalPos(Vector(0, 0, 1))
		ply.RDRHat = brim
	end)
end)

---------------------------------------------------------------- the two gangs
local OUTLAW_MODELS = { "models/humans/group03/male_01.mdl", "models/humans/group03/male_02.mdl", "models/humans/group03/male_03.mdl", "models/humans/group03/male_04.mdl", "models/humans/group03/male_05.mdl", "models/humans/group03/male_06.mdl", "models/humans/group03/male_07.mdl" }
local HAT_COLORS = { Color(125, 85, 50), Color(90, 60, 40), Color(150, 120, 80), Color(70, 55, 45), Color(165, 60, 45) }

local function townSpot(side)
	local C = RDR.C
	if not C then return Sigf.Ground(Sigf.Arena(), 800) end
	local x = side == "law" and math.random(300, 900) or math.random(-900, -300)
	local p = W(x, math.random(-130, 130), 6)
	return p
end

function RDR.SpawnOutlaw(boss)
	local p = townSpot("outlaw")
	local name = boss and BOSS_NAMES[math.random(#BOSS_NAMES)] or OUTLAW_NAMES[math.random(#OUTLAW_NAMES)]
	local e = Sigf.NPC("npc_citizen", p, { weapon = boss and "weapon_shotgun" or Sigf.Pick({ "weapon_357", "weapon_357", "weapon_pistol", "weapon_shotgun" }), keys = { citizentype = 3 }, health = boss and 450 or 70, model = Sigf.Pick(OUTLAW_MODELS), scale = boss and 1.18 or 1 })
	if not IsValid(e) then return end
	e.SigfSide = "rebel"
	e:SetNW2String("rdr_name", name)
	e:SetNW2String("rdr_team", boss and "boss" or "outlaw")
	e:SetNW2Int("rdr_bounty", boss and 500 or math.random(2, 9) * 5)
	e:SetNW2Int("rdr_maxhp", e:GetMaxHealth())
	e:SetColor(Color(215, 195, 165))
	wearHat(e, "outlaw", boss and Color(25, 25, 25) or Sigf.Pick(HAT_COLORS))
	if boss then
		RDR.Boss = e
		Sigf.Sprite("sprites/light_glow02_add", e, 90, 0, { color = Color(255, 50, 30) })
	end
	RDR.Relate(e)
	return e
end

function RDR.SpawnLaw()
	local p = townSpot("law")
	local e = Sigf.NPC("npc_metropolice", p, { weapon = Sigf.Pick({ "weapon_pistol", "weapon_pistol", "weapon_smg1" }), health = 80 })
	if not IsValid(e) then return end
	e.SigfSide = "combine"
	e:SetNW2String("rdr_name", Sigf.Pick(LAW_NAMES))
	e:SetNW2String("rdr_team", "law")
	e:SetNW2Int("rdr_bounty", 0)
	e:SetColor(Color(200, 190, 175))
	wearHat(e, "law", Color(55, 55, 70))
	RDR.Relate(e)
	return e
end

-- the player and the bots are bounty hunters riding with the law; the outlaws shoot them on sight
local function relate(e)
	local t = e:GetNW2String("rdr_team", "")
	for _, p in ipairs(player.GetAll()) do
		if t == "law" then e:AddEntityRelationship(p, D_LI, 99) else e:AddEntityRelationship(p, D_HT, 99) end
	end
end
RDR.Relate = relate

local function census()
	local o, l = 0, 0
	for _, e in ipairs(Sigf.NPCs()) do
		local t = e:GetNW2String("rdr_team", "")
		if t == "outlaw" or t == "boss" then o = o + 1 elseif t == "law" then l = l + 1 end
	end
	return o, l
end

local function gangTick()
	if not RDR.C then return end
	local o, l = census()
	if o < 5 then RDR.SpawnOutlaw(false) end
	if l < 4 then RDR.SpawnLaw() end
	for _, e in ipairs(Sigf.NPCs()) do if e:GetNW2String("rdr_team", "") ~= "" then relate(e) end end
	-- idle gunmen charge the enemy gang so the gunfight never stops
	local list = { law = {}, outlaw = {} }
	for _, e in ipairs(Sigf.NPCs()) do
		local t = e:GetNW2String("rdr_team", "")
		if t == "boss" then t = "outlaw" end
		if list[t] then table.insert(list[t], e) end
	end
	for t, mine in pairs(list) do
		local other = list[t == "law" and "outlaw" or "law"]
		for _, e in ipairs(mine) do
			if not IsValid(e:GetEnemy()) then
				local tg = Sigf.Pick(other)
				if IsValid(tg) then e:SetLastPosition(tg:GetPos()) e:SetSchedule(SCHED_FORCED_GO_RUN) end
			end
		end
	end
end

---------------------------------------------------------------- bounty, cash, honor
local function killedBy(attacker)
	if not IsValid(attacker) then return false end
	if attacker:IsPlayer() then return true end
	return false
end

hook.Add("OnNPCKilled", "rdr_kill", function(npc, attacker, inflictor)
	local team = npc:GetNW2String("rdr_team", "")
	if team == "" then return end
	dropHat(npc)
	local bounty = npc:GetNW2Int("rdr_bounty", 0)
	local pos = npc:WorldSpaceCenter()
	RDR.kills = RDR.kills + 1
	local playerSide = killedBy(attacker)
	if team == "law" then
		if playerSide then
			RDR.honor = math.max(0, RDR.honor - 8)
			net2("float", { pos = pos, text = "LAWMAN DOWN  -HONOR", col = { 255, 90, 70 } })
		else
			net2("float", { pos = pos, text = "Deputy down", col = { 220, 220, 220 } })
		end
	else
		if playerSide or team == "boss" then RDR.cash = RDR.cash + bounty end
		if playerSide then RDR.honor = math.min(100, RDR.honor + 2) end
		net2("float", { pos = pos, text = (team == "boss" and "BOUNTY  +$" or "OUTLAW  +$") .. bounty, col = { 120, 255, 120 } })
	end
	net2("hud", { cash = RDR.cash, honor = RDR.honor })
	if team == "boss" then
		RDR.Boss = nil
		net2("title", { text = "BOUNTY COLLECTED", sub = npc:GetNW2String("rdr_name") .. "  -  $" .. bounty })
		Sigf.Sound2D("sigf/harmonica.wav")
		RDR.chapter = (RDR.chapter or 1) + 1
		local ch = CHAPTERS[(RDR.chapter - 2) % #CHAPTERS + 1]
		Sigf.After(9, function() net2("title", { text = "CHAPTER " .. RDR.chapter, sub = ch }) end)
		net2("obj", { text = "" })
		RDR.bossCooldown = CurTime() + 18
	end
	-- chain: a few kills in a row refill Dead Eye
	RDR.streak = (RDR.streak or 0) + 1
	RDR.streakAt = CurTime()
end)

-- 357 revolver sound for every Magnum shot
hook.Add("EntityEmitSound", "rdr_revolver_sound", function(data)
	local n = data.OriginalSoundName or ""
	if n:find("weapon_357", 1, true) or n:find("357", 1, true) and n:find("Weapon", 1, true) then
		data.SoundName = "sigf/revolver.wav"
		data.Volume = 1
		data.SoundLevel = 100
		data.Pitch = math.random(95, 108)
		return true
	end
end)

-- hits show: blood-colored sparks + a pain grunt are already in the game; add a shove and a dusty puff
hook.Add("EntityTakeDamage", "rdr_hit_shove", function(target, dmg)
	if IsValid(target) and target:IsNPC() and target:GetNW2String("rdr_team", "") ~= "" and dmg:GetDamage() > 4 then
		local f = dmg:GetDamageForce()
		if f:LengthSqr() < 1 then f = (target:GetPos() - (IsValid(dmg:GetAttacker()) and dmg:GetAttacker():GetPos() or target:GetPos())):GetNormalized() * 3000 end
		dmg:SetDamageForce(f * 1.5)
		Sigf.Effect("ThumperDust", target:GetPos() + Vector(0, 0, 8), { scale = 0.4, magnitude = 0.2, radius = 30 })
	end
end)

---------------------------------------------------------------- wanted bounty boss
local function bossTick()
	if not RDR.C then return end
	if IsValid(RDR.Boss) then
		net2("boss", { ent = RDR.Boss:EntIndex(), name = RDR.Boss:GetNW2String("rdr_name"), hp = RDR.Boss:Health(), max = RDR.Boss:GetMaxHealth() })
		return
	end
	if RDR.holdBoss or (RDR.bossCooldown or 0) > CurTime() then return end
	local b = RDR.SpawnOutlaw(true)
	if not IsValid(b) then return end
	local name = b:GetNW2String("rdr_name")
	net2("wanted", { name = name, reward = 500 })
	net2("obj", { text = "Hunt down " .. name .. " - $500 reward" })
	Sigf.Sound2D("sigf/harmonica.wav")
end

---------------------------------------------------------------- Dead Eye
local function hostileTo(shooter)
	local out = {}
	for _, e in ipairs(Sigf.NPCs()) do
		if e:Health() > 0 and e:Disposition(shooter) == D_HT and e:GetPos():Distance(shooter:GetPos()) < 1300 then out[#out + 1] = e end
	end
	table.sort(out, function(a, b) return a:GetPos():DistToSqr(shooter:GetPos()) < b:GetPos():DistToSqr(shooter:GetPos()) end)
	while #out > 5 do table.remove(out) end
	return out
end

function RDR.DeadEye(shooter)
	if RDR.deadeye or not IsValid(shooter) then return end
	local targets = hostileTo(shooter)
	if #targets < 2 then return end
	RDR.deadeye = true
	local ids = {}
	for _, t in ipairs(targets) do ids[#ids + 1] = t:EntIndex() end
	net2("deadeye", { on = true, ids = ids })
	game.SetTimeScale(0.2)
	Sigf.Sound2D("sigf/deadeye.wav")
	-- marking phase (game seconds; time runs at 0.2)
	timer.Simple(0.5, function()
		game.SetTimeScale(0.6)
		local n = 0
		for _, t in ipairs(targets) do
			timer.Simple(n * 0.12, function()
				if not IsValid(shooter) then return end
				if IsValid(t) and t:Health() > 0 then
					local from = shooter:GetShootPos()
					local to = t:WorldSpaceCenter()
					local ed = EffectData()
					ed:SetStart(from) ed:SetOrigin(to) ed:SetEntity(shooter) ed:SetScale(6000)
					util.Effect("Tracer", ed, true, true)
					sound.Play("sigf/revolver.wav", from, 95, math.random(95, 110), 1)
					Sigf.Effect("ManhackSparks", to, { scale = 2 })
					Sigf.Effect("BloodImpact", to, { scale = 1 })
					local dm = DamageInfo()
					dm:SetDamage(math.max(t:Health() + 5, 120))
					dm:SetAttacker(shooter)
					dm:SetInflictor(IsValid(shooter:GetActiveWeapon()) and shooter:GetActiveWeapon() or shooter)
					dm:SetDamageType(DMG_BULLET)
					dm:SetDamageForce((to - from):GetNormalized() * 14000)
					dm:SetDamagePosition(to)
					t:TakeDamage(dm:GetDamage(), shooter, dm:GetInflictor())
				end
			end)
			n = n + 1
		end
		timer.Simple(n * 0.12 + 0.6, function()
			game.SetTimeScale(1)
			RDR.deadeye = false
			net2("deadeye", { on = false })
			RDR.deCool = CurTime() + 14
		end)
	end)
	-- safety: never stay in slow motion
	timer.Simple(6, function() if RDR.deadeye then game.SetTimeScale(1) RDR.deadeye = false net2("deadeye", { on = false }) end end)
end

local function deadEyeTick()
	if Sigf.IsDemo() and not RDR.autoDE then return end
	if RDR.deadeye or (RDR.deCool or 0) > CurTime() then return end
	local best
	local act = Sigf.Action()
	local pool = {}
	for _, p in ipairs(Sigf.Players()) do pool[#pool + 1] = p end
	local h = Sigf.Host()
	if IsValid(h) and Sigf.IsDemo() and h:Alive() then pool[#pool + 1] = h end
	local bd = 1e12
	for _, p in ipairs(pool) do
		if #hostileTo(p) >= 2 then
			local d = p:GetPos():DistToSqr(act)
			if Sigf.IsDemo() and p == h then d = 0 end
			if d < bd then best, bd = p, d end
		end
	end
	if best then RDR.DeadEye(best) end
end
RDR.DeadEyeTick = deadEyeTick

---------------------------------------------------------------- tumbleweeds and the stampede
local function tumbleweed()
	if not RDR.C then return end
	local C = RDR.C
	local p = W(-1100, math.random(-120, 120), 40)
	local e = mkProp("models/hunter/misc/sphere1x1.mdl", p, angle_zero, "sigf/tumble", nil, false)
	if not e then return end
	e:SetModelScale(0.8, 0)
	e:Activate()
	local ph = e:GetPhysicsObject()
	if IsValid(ph) then ph:SetMass(15) ph:Wake() ph:SetVelocity(Wdir(380, math.Rand(-30, 30)) + Vector(0, 0, 80)) end
	e.RDRWeed = true
	SafeRemoveEntityDelayed(e, 25)
end

function RDR.Stampede(from, dir)
	if not RDR.C then return end
	local C = RDR.C
	from = from or W(-1250, 0, 70)
	dir = dir or Wdir(1, 0)
	local side = Vector(-dir.y, dir.x, 0)
	net2("title", { text = "STAMPEDE!", sub = "Horses on the loose" })
	Sigf.Sound2D("sigf/horse.wav")
	local list = {}
	for i = 1, 5 do
		local p = from + side * (-120 + i * 55) - dir * (i % 2) * 60
		local e = mkProp("models/props_c17/statue_horse.mdl", p, dir:Angle(), nil, nil, false)
		if e then
			e:SetModelScale(0.8, 0)
			e:Activate()
			list[#list + 1] = e
			SafeRemoveEntityDelayed(e, 14)
		end
	end
	for k = 0, 24 do
		timer.Simple(k * 0.2, function()
			for _, e in ipairs(list) do
				if IsValid(e) then
					local ph = e:GetPhysicsObject()
					if IsValid(ph) then
						ph:SetVelocity(dir * 1050 + Vector(0, 0, math.min(0, ph:GetVelocity().z)))
					end
					for _, n in ipairs(Sigf.Near(e:GetPos(), 130)) do
						if n:IsNPC() and not n.RDRTrampled then
							n.RDRTrampled = true
							timer.Simple(1, function() if IsValid(n) then n.RDRTrampled = nil end end)
							n:TakeDamage(55, e, e)
							Sigf.Effect("ThumperDust", n:GetPos(), { scale = 2 })
						end
					end
					if k % 3 == 0 then Sigf.Effect("ThumperDust", e:GetPos() - Vector(0, 0, 30), { scale = 1.6 }) end
				end
			end
		end)
	end
end

---------------------------------------------------------------- startup
hook.Add("SigfReady", "rdr_ready", function()
	local function start()
		local base = Sigf.Arena()
		if not base then Sigf.After(1, start) return end
		local tr = util.TraceLine({ start = base + Vector(0, 0, 80), endpos = base - Vector(0, 0, 2000), mask = MASK_SOLID_BRUSHONLY })
		RDR.C = tr.HitPos + Vector(0, 0, 0)
		-- turn the street so both ends open onto free ground
		local bestYaw, bestScore = 0, -1
		for yaw = 0, 165, 15 do
			local d = Angle(0, yaw, 0):Forward()
			local sd = Angle(0, yaw + 90, 0):Forward()
			local function free(dir, len)
				local tr2 = util.TraceHull({ start = RDR.C + Vector(0, 0, 90), endpos = RDR.C + Vector(0, 0, 90) + dir * len, mins = Vector(-30, -30, 0), maxs = Vector(30, 30, 60), mask = MASK_SOLID_BRUSHONLY })
				return tr2.Fraction * len
			end
			local sc = math.min(free(d, 2000), free(-d, 2000)) + 0.25 * math.min(free(sd, 1100), free(-sd, 1100))
			if sc > bestScore then bestScore, bestYaw = sc, yaw end
		end
		RDR.yaw = bestYaw
		print("RDR street yaw " .. bestYaw .. " score " .. math.floor(bestScore))
		print("RDR town center " .. tostring(RDR.C))
		Sigf.Safe("rdr town", function() buildTown(RDR.C) end)
		Sigf.Focus(RDR.C + Vector(0, 0, 40), 14)
		net2("hud", { cash = RDR.cash, honor = RDR.honor })
		net2("title", { text = "DUSTY GULCH", sub = "Chapter 1: Outlaws for Life" })
		Sigf.Safe("rdr sound", function() Sigf.Sound2D("sigf/harmonica.wav") end)
	end
	Sigf.After(0.5, start)
	Sigf.After(2, function() Sigf.Sound2D("sigf/saloon.wav") end)
	Sigf.Every(46, function() Sigf.Sound2D("sigf/saloon.wav") end)
	Sigf.Every(3, function() gangTick() end)
	Sigf.Every(1.5, function() bossTick() end)
	Sigf.Every(5, function() deadEyeTick() end)
	Sigf.Every(7, function() tumbleweed() end)
	Sigf.Every(55, function() RDR.Stampede() end)
	Sigf.Every(1, function()
		if RDR.C then
			for _, e in ipairs(ents.FindByClass("prop_physics")) do
				if e.RDRWeed then
					local ph = e:GetPhysicsObject()
					if IsValid(ph) then ph:ApplyForceCenter(Wdir(2500, math.Rand(-1500, 1500)) + Vector(0, 0, 600)) end
				end
			end
		end
	end)
end)

-- the Magnum is a quick revolver: fan the hammer
hook.Add("EntityFireBullets", "rdr_fan_hammer", function(ent, data)
	if ent:IsPlayer() then
		local w = ent:GetActiveWeapon()
		if IsValid(w) and w:GetClass() == "weapon_357" then
			timer.Simple(0, function() if IsValid(w) then w:SetNextPrimaryFire(CurTime() + 0.3) end end)
		end
	end
end)

