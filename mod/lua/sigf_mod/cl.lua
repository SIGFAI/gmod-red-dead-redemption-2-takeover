-- Red Dead Redemption 2 Takeover: client side. Sepia frontier look, Dead Eye, western HUD, signs, floating bounty text.
local S = { cash = 0, honor = 60, deadeye = false, deAt = 0, deEnd = 0, ids = {}, floats = {}, title = nil, obj = "", objAt = 0, wanted = nil, boss = nil }

local function fnt(name, size, weight, font)
	surface.CreateFont(name, { font = font or "Georgia", size = math.floor(size * ScrH() / 1080), weight = weight or 800, antialias = true })
end
local function mk()
	fnt("RDR_Big", 92, 900)
	fnt("RDR_Mid", 40, 800)
	fnt("RDR_Sm", 26, 700)
	fnt("RDR_Tiny", 20, 700)
	fnt("RDR_Cash", 44, 900)
	fnt("RDR_Float", 30, 900, "Georgia")
	fnt("RDR_Sign", 200, 900, "Georgia")
end
mk()
hook.Add("OnScreenSizeChanged", "rdr_fonts", mk)

local wantedMat = Material("sigf/wanted")

net.Receive("rdr_msg", function()
	local kind = net.ReadString()
	local d = net.ReadTable()
	local now = RealTime()
	if kind == "hud" then
		S.cash, S.honor = d.cash or S.cash, d.honor or S.honor
		S.cashAt = now
	elseif kind == "deadeye" then
		if d.on then
			S.deadeye = true
			S.deAt = now
			S.ids = d.ids or {}
		else
			S.deadeye = false
			S.deEnd = now
		end
	elseif kind == "float" then
		S.floats[#S.floats + 1] = { pos = d.pos + Vector(math.random(-40, 40), math.random(-40, 40), math.random(0, 50)), text = d.text, col = d.col or { 255, 255, 255 }, at = now }
		while #S.floats > 7 do table.remove(S.floats, 1) end
	elseif kind == "title" then
		S.title = { text = d.text, sub = d.sub, at = now }
	elseif kind == "obj" then
		S.obj = d.text or ""
		S.objAt = now
	elseif kind == "wanted" then
		S.wanted = { name = d.name, reward = d.reward, at = now }
	elseif kind == "boss" then
		S.boss = d
		S.bossAt = now
	end
end)

---------------------------------------------------------------- the look: dusty sepia, vignette, film grain, fog
local fogOn = true
hook.Add("SetupWorldFog", "rdr_fog", function()
	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(500)
	render.FogEnd(3400)
	render.FogMaxDensity(0.88)
	render.FogColor(214, 172, 118)
	return true
end)
hook.Add("SetupSkyboxFog", "rdr_skyfog", function(scale)
	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(0)
	render.FogEnd(700 * scale)
	render.FogMaxDensity(0.9)
	render.FogColor(226, 160, 100)
	return true
end)

local function deK()
	local now = RealTime()
	if S.deadeye then return math.Clamp((now - S.deAt) / 0.35, 0, 1) end
	return math.Clamp(1 - (now - S.deEnd) / 0.6, 0, 1)
end

hook.Add("RenderScreenspaceEffects", "rdr_look", function()
	local k = deK()
	DrawColorModify({
		["$pp_colour_addr"] = 0.09 * (1 - k) + 0.02 * k,
		["$pp_colour_addg"] = 0.035 * (1 - k),
		["$pp_colour_addb"] = -0.07 * (1 - k) - 0.03 * k,
		["$pp_colour_brightness"] = -0.04 - 0.06 * k,
		["$pp_colour_contrast"] = 1.18 + 0.2 * k,
		["$pp_colour_colour"] = 0.5 - 0.35 * k,
		["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
	})
	DrawBloom(0.7, 0.5 + 0.6 * k, 6, 6, 1, 1.0, 1, 0.9, 0.7)
	if k > 0.01 then DrawMotionBlur(0.2, 0.7 * k, 0.012) end
end)

local gradL = Material("vgui/gradient-l")
local gradR = Material("vgui/gradient-r")
local gradU = Material("vgui/gradient-u")
local gradD = Material("vgui/gradient-d")

local function vignette(a, w)
	local sw, sh = ScrW(), ScrH()
	surface.SetDrawColor(30, 12, 0, a)
	surface.SetMaterial(gradL) surface.DrawTexturedRect(0, 0, sw * w, sh)
	surface.SetMaterial(gradR) surface.DrawTexturedRect(sw * (1 - w), 0, sw * w, sh)
	surface.SetMaterial(gradU) surface.DrawTexturedRect(0, 0, sw, sh * w * 1.4)
	surface.SetMaterial(gradD) surface.DrawTexturedRect(0, sh * (1 - w * 1.4), sw, sh * w * 1.4)
end

local function circle(cx, cy, r, seg, from, to)
	local pts = { { x = cx, y = cy } }
	from, to = from or 0, to or 360
	for i = 0, seg do
		local a = math.rad(from + (to - from) * i / seg - 90)
		pts[#pts + 1] = { x = cx + math.cos(a) * r, y = cy + math.sin(a) * r }
	end
	surface.DrawPoly(pts)
end

local function ring(cx, cy, r, frac, col, thick)
	draw.NoTexture()
	surface.SetDrawColor(0, 0, 0, 170)
	circle(cx, cy, r + 3, 40)
	surface.SetDrawColor(40, 36, 30, 220)
	circle(cx, cy, r, 40)
	surface.SetDrawColor(col.r, col.g, col.b, 240)
	circle(cx, cy, r - 3, 40, 0, 360 * frac)
	surface.SetDrawColor(20, 16, 12, 255)
	circle(cx, cy, r - thick, 40)
end

---------------------------------------------------------------- HUD
local function worldText(pos, text, col, font, alpha)
	local sp = pos:ToScreen()
	if not sp.visible then return end
	draw.SimpleTextOutlined(text, font or "RDR_Float", sp.x, sp.y, Color(col[1], col[2], col[3], alpha or 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, alpha or 255))
end

local radarR = 0
hook.Add("HUDPaintBackground", "rdr_hud_bg", function()
	local sw, sh = ScrW(), ScrH()
	local k = deK()
	vignette(120 + 120 * k, 0.28)
	if k > 0.02 then
		-- Dead Eye: red tint pulse
		local pulse = 0.5 + 0.5 * math.sin(RealTime() * 7)
		surface.SetDrawColor(170, 20, 10, 24 * k + 24 * k * pulse)
		surface.DrawRect(0, 0, sw, sh)
	end
	-- cinematic black bars
	local bar = sh * (0.045 + 0.04 * k)
	surface.SetDrawColor(0, 0, 0, 255)
	surface.DrawRect(0, 0, sw, bar)
	surface.DrawRect(0, sh - bar, sw, bar)
	-- film grain
	surface.SetDrawColor(255, 240, 210, 22)
	for i = 1, 60 do surface.DrawRect(math.random(0, sw), math.random(0, sh), 2, 2) end
end)

hook.Add("HUDPaint", "rdr_hud", function()
	local sw, sh = ScrW(), ScrH()
	local now = RealTime()
	local lp = LocalPlayer()
	local ep = EyePos()
	local k = deK()
	local sc = sh / 1080

	-- name tags over gunmen (nearest first, a tag never covers another one)
	local tags = {}
	local npcs = ents.FindByClass("npc_*")
	table.sort(npcs, function(a, b) return a:GetPos():DistToSqr(ep) < b:GetPos():DistToSqr(ep) end)
	for _, e in ipairs(npcs) do
		local team = e:GetNW2String("rdr_team", "")
		if team ~= "" and e:Health() > 0 then
			local d = ep:Distance(e:GetPos())
			local seen = d < 1000 and util.TraceLine({ start = ep, endpos = e:WorldSpaceCenter(), mask = MASK_SOLID, filter = function(x) return x:IsWorld() or x:GetNW2Bool("rdr_town", false) end }).Fraction > 0.98
			if seen then
				local a = math.Clamp((1000 - d) / 400, 0, 1) * 255
				local top = e:GetPos() + Vector(0, 0, e:OBBMaxs().z + 22)
				local sp = top:ToScreen()
				for _, t in ipairs(tags) do
					if math.abs(t.x - sp.x) < 150 * sc and math.abs(t.y - sp.y) < 46 * sc then sp.visible = false end
				end
				if sp.visible then
					tags[#tags + 1] = sp
					local c = team == "law" and Color(150, 190, 255, a) or (team == "boss" and Color(255, 90, 60, a) or Color(255, 230, 160, a))
					draw.SimpleTextOutlined(e:GetNW2String("rdr_name"), "RDR_Sm", sp.x, sp.y, c, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0, a))
					local b = e:GetNW2Int("rdr_bounty", 0)
					if b > 0 then draw.SimpleTextOutlined("WANTED  $" .. b, "RDR_Tiny", sp.x, sp.y + 2, Color(255, 120, 90, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, a)) end
				end
			end
		end
	end

	-- Dead Eye marks on the painted targets
	if S.deadeye or k > 0.02 then
		for i, id in ipairs(S.ids) do
			local e = Entity(id)
			local born = (S.deadeye and (now - S.deAt) or 9) - 0.25 - (i - 1) * 0.3
			if IsValid(e) and e:Health() > 0 and born > 0 then
				local sp = e:WorldSpaceCenter():ToScreen()
				if sp.visible then
					local snap = 1 + math.max(0, 0.25 - born) * 8
					local s = (30 + 4 * math.sin(now * 9)) * sc * snap
					local al = 255 * math.min(k, 1)
					surface.SetDrawColor(255, 40, 30, al)
					for w = -2, 2 do
						surface.DrawLine(sp.x - s + w, sp.y - s, sp.x + s + w, sp.y + s)
						surface.DrawLine(sp.x - s + w, sp.y + s, sp.x + s + w, sp.y - s)
					end
					surface.DrawCircle(sp.x, sp.y, s * 1.6, 255, 60, 40, al)
					surface.DrawCircle(sp.x, sp.y, s * 1.6 + 2, 255, 60, 40, al)
				end
			end
		end
		draw.SimpleTextOutlined("DEAD EYE", "RDR_Big", sw / 2, sh * 0.80, Color(255, 70, 50, 255 * k), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 3, Color(0, 0, 0, 255 * k))
	end

	-- floating bounty text
	for i = #S.floats, 1, -1 do
		local f = S.floats[i]
		local t = now - f.at
		if t > 2.8 then table.remove(S.floats, i) else
			worldText(f.pos + Vector(0, 0, 30 + t * 40), f.text, f.col, "RDR_Float", 255 * math.Clamp(1 - (t - 1.8) / 1, 0, 1))
		end
	end

	-- cash, top right
	local cx = sw - 40 * sc
	draw.SimpleTextOutlined("$" .. string.format("%d.%02d", S.cash, 0), "RDR_Cash", cx, sh * 0.075, Color(235, 225, 190), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, 255))

	-- radar bottom left: parchment disc, outlaws red, lawmen blue
	local rr = 100 * sc
	local rx, ry = 150 * sc, sh - 160 * sc
	draw.NoTexture()
	surface.SetDrawColor(0, 0, 0, 200) circle(rx, ry, rr + 5, 48)
	surface.SetDrawColor(196, 170, 120, 225) circle(rx, ry, rr, 48)
	local yaw = EyeAngles().y
	for _, e in ipairs(ents.GetAll()) do
		if (e:IsNPC() and e:Health() > 0) or (e:IsPlayer() and e ~= lp and e:Alive() and not e:GetNoDraw()) then
			local rel = e:GetPos() - ep
			local x = rel.x * math.cos(math.rad(yaw - 90)) - rel.y * math.sin(math.rad(yaw - 90))
			local y = rel.x * math.sin(math.rad(yaw - 90)) + rel.y * math.cos(math.rad(yaw - 90))
			x, y = x * 0.06 * sc, -y * 0.06 * sc
			local l = math.sqrt(x * x + y * y)
			if l > rr - 6 then x, y = x / l * (rr - 6), y / l * (rr - 6) end
			local team = e:GetNW2String("rdr_team", "")
			local col = team == "law" and Color(40, 80, 200) or ((team == "outlaw" or team == "boss") and Color(190, 30, 20) or Color(40, 140, 40))
			surface.SetDrawColor(col.r, col.g, col.b, 255)
			circle(rx + x, ry + y, team == "boss" and 7 * sc or 5 * sc, 10)
		end
	end
	surface.SetDrawColor(20, 20, 20, 255)
	circle(rx, ry, 5 * sc, 8)
	surface.SetDrawColor(40, 30, 20, 255)
	surface.DrawLine(rx, ry - rr, rx, ry - rr + 14 * sc)
	draw.SimpleText("N", "RDR_Tiny", rx, ry - rr - 12 * sc, Color(235, 225, 190), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	-- cores
	local hp = lp:Alive() and math.Clamp(lp:Health() / math.max(lp:GetMaxHealth(), 1), 0, 1) or 0
	if lp:GetNoDraw() then hp = 1 end
	ring(rx + rr + 55 * sc, ry + 40 * sc, 30 * sc, hp, Color(220, 60, 50), 9 * sc)
	local de = S.deadeye and (1 - math.Clamp((now - S.deAt) / 3, 0, 0.9)) or 1
	ring(rx + rr + 55 * sc, ry - 28 * sc, 30 * sc, de, Color(235, 215, 90), 9 * sc)
	-- honor
	draw.SimpleTextOutlined("HONOR", "RDR_Tiny", 40 * sc, sh * 0.075 - 22 * sc, Color(235, 225, 190), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0))
	surface.SetDrawColor(0, 0, 0, 200) surface.DrawRect(40 * sc - 2, sh * 0.075 - 2, 204 * sc, 14 * sc)
	surface.SetDrawColor(235, 225, 190, 255) surface.DrawRect(40 * sc, sh * 0.075, 200 * sc * S.honor / 100, 10 * sc)

	-- objective
	if S.obj ~= "" then
		local a = 255
		draw.SimpleTextOutlined(S.obj, "RDR_Sm", sw - 40 * sc, sh * 0.075 + 56 * sc, Color(255, 215, 120, a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, a))
	end

	-- boss bar
	if S.boss and now - (S.bossAt or 0) < 3 then
		local b = S.boss
		local w = 520 * sc
		local x0, y0 = sw / 2 - w / 2, sh * 0.08
		draw.SimpleTextOutlined(b.name .. "  -  WANTED", "RDR_Sm", sw / 2, y0 - 10 * sc, Color(255, 120, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0))
		surface.SetDrawColor(0, 0, 0, 220) surface.DrawRect(x0 - 3, y0 - 3, w + 6, 20 * sc + 6)
		surface.SetDrawColor(190, 40, 30, 255) surface.DrawRect(x0, y0, w * math.Clamp(b.hp / math.max(b.max, 1), 0, 1), 20 * sc)
	end

	-- wanted poster slides in when a new bounty appears
	if S.wanted then
		local t = now - S.wanted.at
		if t > 6.5 then S.wanted = nil else
			local slide = math.Clamp(t / 0.4, 0, 1)
			local out = math.Clamp((6.5 - t) / 0.5, 0, 1)
			local ph = sh * 0.52
			local pw = ph * 0.75
			local x = Lerp(math.min(slide, out), sw + 20, sw - pw - 50 * sc)
			surface.SetMaterial(wantedMat)
			surface.SetDrawColor(255, 255, 255, 255)
			local rot = -4 + math.sin(now * 2) * 1.2
			surface.DrawTexturedRectRotated(x + pw / 2, sh * 0.55, pw, ph, rot)
			draw.RoundedBox(6, x - 10 * sc, sh * 0.55 + ph * 0.52, pw + 20 * sc, 44 * sc, Color(30, 14, 6, 230))
			draw.SimpleText(S.wanted.name .. "  $" .. S.wanted.reward, "RDR_Sm", x + pw / 2, sh * 0.55 + ph * 0.52 + 22 * sc, Color(255, 220, 140), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	-- big title card (chapter, bounty collected...)
	if S.title then
		local t = now - S.title.at
		if t > 4.5 then S.title = nil else
			local a = 255 * math.Clamp(t / 0.4, 0, 1) * math.Clamp((4.5 - t) / 0.7, 0, 1)
			surface.SetDrawColor(20, 8, 2, 170 * a / 255)
			surface.DrawRect(0, sh * 0.34 - 62 * sc, sw, 190 * sc)
			draw.SimpleTextOutlined(S.title.text, "RDR_Big", sw / 2, sh * 0.34, Color(235, 215, 150, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 3, Color(40, 10, 0, a))
			if S.title.sub then draw.SimpleTextOutlined(S.title.sub, "RDR_Mid", sw / 2, sh * 0.34 + 74 * sc, Color(240, 230, 200, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, a)) end
		end
	end
end)

---------------------------------------------------------------- shop signs on the buildings
hook.Add("PostDrawOpaqueRenderables", "rdr_signs", function(depth, sky)
	if sky then return end
	for _, e in ipairs(ents.FindByClass("prop_dynamic")) do
		local txt = e:GetNW2String("rdr_st", "")
		if txt ~= "" then
			local ang = e:GetNW2Angle("rdr_sa", Angle(0, 0, 0))
			local sz = e:GetNW2Int("rdr_ss", 60)
			local c = e:GetNW2Vector("rdr_sc", Vector(240, 220, 170))
			cam.Start3D2D(e:GetPos(), ang, 0.21)
				surface.SetFont("RDR_Sign")
				local w, h = surface.GetTextSize(txt)
				local s = sz / 60
				draw.RoundedBox(12, -w / 2 - 30, -h / 2 + 10, w + 60, h - 20, Color(40, 24, 12, 245))
				draw.SimpleText(txt, "RDR_Sign", 0, 0, Color(c.x, c.y, c.z), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			cam.End3D2D()
			cam.Start3D2D(e:GetPos(), Angle(ang.p, ang.y + 180, ang.r), 0.21)
				draw.RoundedBox(12, -w / 2 - 30, -h / 2 + 10, w + 60, h - 20, Color(40, 24, 12, 245))
				draw.SimpleText(txt, "RDR_Sign", 0, 0, Color(c.x, c.y, c.z), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			cam.End3D2D()
		end
	end
end)

---------------------------------------------------------------- stream camera: same as the kit's, but town walls block it
local function clear(from, to)
	local tr = util.TraceHull({ start = from, endpos = to, mins = Vector(-10, -10, -10), maxs = Vector(10, 10, 10), mask = MASK_SOLID, filter = function(e) return e:IsWorld() or e:GetNW2Bool("rdr_town", false) end })
	return tr.HitPos
end
local smooth, yaw = nil, 0
hook.Add("CalcView", "sigf_stage_cam", function(ply, origin, angles, fov)
	local st = Sigf.Stage()
	if st == "demo" and GetGlobalFloat("rdr_cam_until", 0) > CurTime() then
		local p = GetGlobalVector("rdr_cam_pos", origin)
		local look = GetGlobalVector("rdr_cam_look", origin)
		return { origin = p, angles = (look - p):Angle(), fov = 70, drawviewer = true }
	end
	if st == "demo" then
		local eye = ply:EyePos()
		local want = eye - angles:Forward() * 150 + angles:Right() * 30 + Vector(0, 0, 25)
		return { origin = clear(eye, want), angles = angles, fov = 78, drawviewer = true }
	end
	if st ~= "idle" and st ~= "mod" then return end
	local ent = GetGlobalEntity("sigf_focus")
	local target = IsValid(ent) and ent:WorldSpaceCenter() or GetGlobalVector("sigf_focus_pos", origin)
	yaw = (yaw + FrameTime() * 6) % 360
	local wide = math.floor(RealTime() / 10) % 2 == 0
	if wide then
		-- crane shot over Dusty Gulch
		local c = GetGlobalVector("sigf_arena", target) + Vector(0, 0, 60)
		local dir = Angle(24, yaw * 0.5 + 200, 0):Forward()
		local cam = clear(c, c - dir * 1250)
		smooth = nil
		return { origin = cam, angles = (c - cam):Angle(), fov = 72, drawviewer = false }
	end
	if not smooth or smooth:DistToSqr(target) > 1500 * 1500 then smooth = target end
	smooth = LerpVector(math.Clamp(FrameTime() * 2.5, 0, 1), smooth, target)
	local dir = Angle(16, yaw, 0):Forward()
	local center = smooth + Vector(0, 0, 36)
	local cam = clear(center, center - dir * 420 + Vector(0, 0, 70))
	return { origin = cam, angles = (center - cam):Angle(), fov = 72, drawviewer = false }
end)
