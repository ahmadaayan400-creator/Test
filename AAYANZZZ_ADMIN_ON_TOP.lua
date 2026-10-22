--==================================================
-- AAYANZZZ ADMIN ON TOP  |  AAYAN ADMIN V3 ULTIMATE UNIVERSAL CONTROL HUB
-- Client-side utility hub for your own character / camera.
--
-- HONEST NOTES
--  * Everything here runs LOCALLY on your client. Fly, noclip, speed,
--    jump and teleport can be overridden by server replication or blocked
--    by a game's own anti-cheat. Nothing here fakes server permission.
--  * Clipboard copy needs an executor that provides setclipboard.
--  * Free camera / first person / zoom depend on the game's camera setup.
--  * For your OWN game a server-authorised script is provided in
--    AAYAN_ADMIN_V3_Server.lua (optional, allow-list of UserIds).
--  * No data collection, no remote calls except the optional remote you
--    install yourself. Every effect is reversible (EMERGENCY RESET).
--==================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Stats = game:GetService("Stats")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VERSION = "3.0.0"
local CYAN = Color3.fromRGB(0, 220, 255)
local PURPLE = Color3.fromRGB(170, 70, 255)
local NAVY = Color3.fromRGB(8, 10, 24)
local NAVY2 = Color3.fromRGB(16, 20, 44)
local ROW = Color3.fromRGB(18, 22, 48)

-- re-execute safely: shut the previous copy down first
if _G.AAYAN_ADMIN_SHUTDOWN then
	pcall(_G.AAYAN_ADMIN_SHUTDOWN)
end

local COUNT_FILE = "AAYAN_ADMIN_V3_runs.txt"
local runCount, runSaved = 0, false
do
	local n = 0
	pcall(function()
		if isfile and readfile and isfile(COUNT_FILE) then n = tonumber(readfile(COUNT_FILE)) or 0 end
	end)
	n = n + 1
	local ok = pcall(function() writefile(COUNT_FILE, tostring(n)) end)
	if ok then
		runCount, runSaved = n, true
	else
		_G.AAYAN_ADMIN_RUNS = (_G.AAYAN_ADMIN_RUNS or 0) + 1
		runCount = _G.AAYAN_ADMIN_RUNS
	end
end

local function Boot()

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	do
		local old = playerGui:FindFirstChild("AAYAN_ADMIN_V3")
		if old then old:Destroy() end
		local om = workspace:FindFirstChild("AAYAN_ADMIN_MARKERS")
		if om then om:Destroy() end
	end

	--==============================================
	-- STATE
	--==============================================

	local conns = {}
	local alive = true
	local startClock = os.clock()

	local S = {
		-- movement
		fly = false, flySpeed = 60, camRel = true,
		noclip = false,
		walkOn = false, walk = 16,
		jumpOn = false, jump = 50,
		infJump = false, sprint = false, airCtl = false, slowFall = false,
		autoRotate = true, yaw = 0,
		up = false, down = false, dashPower = 85,
		-- camera
		fovOn = false, fov = 70, sens = 1, smooth = false, lock = false, free = false,
		-- visuals
		aura = false, auraIdx = 1, particles = false, trail = false, neon = false, fx = 0.6,
		-- tools
		markers = false, navigate = false, selWp = 0,
		-- gui
		scale = 1, bgTrans = 0.05, rowH = 38, sfx = true, reduceAnim = false,
		perf = false, rgb = false, quickTop = false, serverMode = false,
	}

	local DEFAULT_GUI = {
		scale = 1, bgTrans = 0.05, rowH = 38, sfx = true, reduceAnim = false,
		perf = false, rgb = false, quickTop = false,
	}

	local Def = { walk = 16, jump = 50, useJP = true, fov = 70, minZoom = 0.5, maxZoom = 128, sens = 1 }
	local Theme = { A1 = CYAN, A2 = PURPLE }
	local favs = {}
	local collapsed = {}
	local history = {}
	local wps = {}
	local savedPreset = nil
	local prevCF = nil
	local spawnCF = nil
	local curTab = "MOVE"
	local F = {}          -- feature functions
	local UI = {}         -- ui handles
	local rows = {}       -- every row
	local accents = {}    -- gradients that follow the accent colour
	local refreshers = {} -- functions that refresh row visuals
	local statusLabels = {}
	local Sh = {}   -- active shields
	local W = {}    -- weather system

	local function bind(signal, fn)
		local c = signal:Connect(fn)
		conns[#conns + 1] = c
		return c
	end

	--==============================================
	-- UI HELPERS
	--==============================================

	local function new(class, props, parent)
		local o = Instance.new(class)
		for k, v in pairs(props) do o[k] = v end
		if parent then o.Parent = parent end
		return o
	end

	local function tween(obj, t, props, style, dir)
		if S.reduceAnim then t = 0.01 end
		local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
		tw:Play()
		return tw
	end

	local function corner(p, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, p) end

	local function stroke(p, color, th, tr)
		local mode = p:IsA("TextLabel") and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
		return new("UIStroke", {
			Color = color or Color3.new(1, 1, 1), Thickness = th or 1, Transparency = tr or 0,
			ApplyStrokeMode = mode,
		}, p)
	end

	local function accentGrad(parent, rot)
		local g = new("UIGradient", { Color = ColorSequence.new(Theme.A1, Theme.A2), Rotation = rot or 0 }, parent)
		accents[#accents + 1] = g
		return g
	end

	local function applyTheme()
		for i = #accents, 1, -1 do
			local g = accents[i]
			if g.Parent then
				g.Color = ColorSequence.new(Theme.A1, Theme.A2)
			else
				table.remove(accents, i)
			end
		end
	end

	local function lbl(parent, text, size, color, font, props)
		local l = new("TextLabel", {
			BackgroundTransparency = 1, Text = text, TextSize = size or 12,
			TextColor3 = color or Color3.new(1, 1, 1), Font = font or Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, parent)
		if props then for k, v in pairs(props) do l[k] = v end end
		return l
	end

	local function fmt1(v) return string.format("%.1f", v) end
	local function fmt0(v) return string.format("%d", math.floor(v + 0.5)) end
	local function v3s(v) return string.format("%.1f, %.1f, %.1f", v.X, v.Y, v.Z) end

	local function getChar() return player.Character end
	local function getHum()
		local c = player.Character
		return c and c:FindFirstChildOfClass("Humanoid")
	end
	local function getRoot()
		local c = player.Character
		return c and c:FindFirstChild("HumanoidRootPart")
	end

	--==============================================
	-- GUI ROOT
	--==============================================

	local sg = new("ScreenGui", {
		Name = "AAYAN_ADMIN_V3",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	local clickSnd = new("Sound", { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25 }, sg)
	local function click()
		if S.sfx then pcall(function() clickSnd.TimePosition = 0 clickSnd:Play() end) end
	end

	--==============================================
	-- NOTIFICATIONS + HISTORY
	--==============================================

	local toastHolder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(280, 260), BackgroundTransparency = 1, ZIndex = 300,
	}, sg)
	new("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
	}, toastHolder)
	local toastOrder = 0
	local liveToasts = {}

	local function logHistory(text)
		table.insert(history, 1, string.format("[%s] %s", os.date("%H:%M:%S"), text))
		while #history > 40 do table.remove(history) end
	end

	local function notify(title, sub, kind)
		logHistory(title .. (sub and (" - " .. sub) or ""))
		if not alive then return end
		toastOrder = toastOrder + 1
		local col = (kind == "on" and Color3.fromRGB(90, 255, 150))
			or (kind == "off" and Color3.fromRGB(255, 100, 110))
			or (kind == "warn" and Color3.fromRGB(255, 200, 80))
			or CYAN

		local w = new("Frame", { LayoutOrder = toastOrder, Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, ZIndex = 300 }, toastHolder)
		table.insert(liveToasts, w)
		while #liveToasts > 4 do
			local o = table.remove(liveToasts, 1)
			if o and o.Parent then o:Destroy() end
		end

		local card = new("Frame", {
			Size = UDim2.new(1, 0, 1, 0), Position = UDim2.fromOffset(0, 40),
			BackgroundColor3 = NAVY2, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 301,
		}, w)
		corner(card, 12)
		local st = stroke(card, Color3.new(1, 1, 1), 1.6, 0)
		accentGrad(st, 0)
		local bar = new("Frame", {
			Position = UDim2.new(0, 8, 0.5, -13), Size = UDim2.fromOffset(4, 26),
			BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = 302,
		}, card)
		corner(bar, 3)
		local t1 = lbl(card, title, 13, Color3.new(1, 1, 1), Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(20, 4), Size = UDim2.new(1, -28, 0, 20),
			TextTransparency = 1, ZIndex = 303, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local t2 = lbl(card, sub or "", 11, col, Enum.Font.Gotham, {
			Position = UDim2.fromOffset(20, 23), Size = UDim2.new(1, -28, 0, 16),
			TextTransparency = 1, ZIndex = 303, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		tween(card, 0.3, { Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 0.05 }, Enum.EasingStyle.Back)
		tween(t1, 0.25, { TextTransparency = 0 })
		tween(t2, 0.25, { TextTransparency = 0 })

		task.delay(2.2, function()
			if not w.Parent then return end
			tween(card, 0.3, { Position = UDim2.fromOffset(0, 36), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(t1, 0.25, { TextTransparency = 1 })
			tween(t2, 0.25, { TextTransparency = 1 })
			task.delay(0.35, function() if w.Parent then w:Destroy() end end)
		end)
	end

	-- big banner in the middle of the screen: avatar + name + execution count
	local function banner()
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -30),
			Size = UDim2.fromOffset(350, 112), BackgroundColor3 = NAVY, BackgroundTransparency = 1,
			BorderSizePixel = 0, ZIndex = 400,
		}, sg)
		corner(f, 20)
		local st = stroke(f, Color3.new(1, 1, 1), 2.6, 1)
		accentGrad(st, 0)
		local sc = new("UIScale", { Scale = 0.7 }, f)

		local ring = new("Frame", {
			Position = UDim2.fromOffset(16, 18), Size = UDim2.fromOffset(76, 76), BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 401,
		}, f)
		corner(ring, 38)
		accentGrad(ring, 45)
		local av = new("ImageLabel", {
			Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), BackgroundColor3 = NAVY2,
			BorderSizePixel = 0, ImageTransparency = 1, ZIndex = 402,
			Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150",
		}, ring)
		corner(av, 36)

		local a = lbl(f, "AAYAN ADMIN LOADED", 18, Color3.new(1, 1, 1), Enum.Font.GothamBlack, {
			Position = UDim2.fromOffset(106, 10), Size = UDim2.new(1, -112, 0, 26), TextTransparency = 1, ZIndex = 402,
		})
		accentGrad(a, 0)
		local nm = lbl(f, player.DisplayName .. "  (@" .. player.Name .. ")", 12, Color3.fromRGB(210, 225, 255), Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(106, 38), Size = UDim2.new(1, -112, 0, 18), TextTransparency = 1, ZIndex = 402,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local ex = lbl(f, "EXECUTED  " .. runCount .. (runCount == 1 and " TIME" or " TIMES"), 14, CYAN, Enum.Font.GothamBlack, {
			Position = UDim2.fromOffset(106, 60), Size = UDim2.new(1, -112, 0, 20), TextTransparency = 1, ZIndex = 402,
		})
		local ex2 = lbl(f, runSaved and "counted on this device" or "counted this session only", 10, Color3.fromRGB(150, 165, 210), Enum.Font.Gotham, {
			Position = UDim2.fromOffset(106, 82), Size = UDim2.new(1, -112, 0, 14), TextTransparency = 1, ZIndex = 402,
		})

		local labels = { a, nm, ex, ex2 }
		tween(f, 0.5, { BackgroundTransparency = 0.06 })
		tween(st, 0.5, { Transparency = 0 })
		tween(ring, 0.5, { BackgroundTransparency = 0 })
		tween(av, 0.5, { ImageTransparency = 0 })
		tween(sc, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
		for _, l in ipairs(labels) do tween(l, 0.5, { TextTransparency = 0 }) end

		task.delay(3.4, function()
			if not f.Parent then return end
			tween(f, 0.5, { BackgroundTransparency = 1 })
			tween(st, 0.5, { Transparency = 1 })
			tween(ring, 0.5, { BackgroundTransparency = 1 })
			tween(av, 0.5, { ImageTransparency = 1 })
			tween(sc, 0.5, { Scale = 0.85 })
			for _, l in ipairs(labels) do tween(l, 0.4, { TextTransparency = 1 }) end
			task.delay(0.6, function() if f.Parent then f:Destroy() end end)
		end)
	end

	--==============================================
	-- MODALS (confirmation + info)
	--==============================================

	local modal = new("Frame", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5, BorderSizePixel = 0, Visible = false, ZIndex = 350, Active = true,
	}, sg)
	local modalCard = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(280, 170), BackgroundColor3 = NAVY, BorderSizePixel = 0, ZIndex = 351,
	}, modal)
	corner(modalCard, 16)
	accentGrad(stroke(modalCard, Color3.new(1, 1, 1), 2, 0), 45)
	new("UIScale", {}, modalCard)
	local modalTitle = lbl(modalCard, "", 15, Color3.new(1, 1, 1), Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 22), ZIndex = 352,
	})
	local modalBody = lbl(modalCard, "", 12, Color3.fromRGB(190, 200, 235), Enum.Font.Gotham, {
		Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 1, -90), ZIndex = 352,
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
	})
	local modalBtns = new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -12),
		Size = UDim2.new(1, -28, 0, 34), BackgroundTransparency = 1, ZIndex = 352,
	}, modalCard)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
	}, modalBtns)
	local modalYes, modalNo

	local function modalButton(text, color)
		local b = new("TextButton", {
			Size = UDim2.fromOffset(100, 32), BackgroundColor3 = color, Text = text,
			TextColor3 = Color3.new(1, 1, 1), TextSize = 12, Font = Enum.Font.GothamBlack,
			AutoButtonColor = true, ZIndex = 353,
		}, modalBtns)
		corner(b, 10)
		return b
	end
	modalNo = modalButton("CANCEL", Color3.fromRGB(50, 56, 100))
	modalYes = modalButton("CONFIRM", Color3.fromRGB(190, 50, 90))

	local modalCb = nil
	local function closeModal() modal.Visible = false modalCb = nil end
	bind(modalNo.Activated, closeModal)
	bind(modalYes.Activated, function()
		local cb = modalCb
		closeModal()
		if cb then cb() end
	end)

	local function confirm(title, body, cb)
		modalTitle.Text = title
		modalBody.Text = body
		modalYes.Visible = true
		modalNo.Text = "CANCEL"
		modalCb = cb
		modalCard.Size = UDim2.fromOffset(280, 160)
		modal.Visible = true
	end

	local function infoModal(title, body, height)
		modalTitle.Text = title
		modalBody.Text = body
		modalYes.Visible = false
		modalNo.Text = "CLOSE"
		modalCb = nil
		modalCard.Size = UDim2.fromOffset(300, height or 300)
		modal.Visible = true
	end

	--==============================================
	-- FEATURE LOGIC
	--==============================================

	local flyBV, flyBG
	local origCollide = {}
	local origLook = {}
	local fxObjs = {}
	local walkApplied, jumpApplied = false, false
	local dashUntil, dashDir, lastDash = 0, Vector3.zero, 0
	local ownMoveUntil = 0
	local fc = { yaw = 0, pitch = 0, pos = Vector3.zero }
	local smoothCF, lockCF
	local markerFolder
	local markerLabels = {}
	local spectating = nil

	local AURAS = {
		{ "CYAN", CYAN, PURPLE },
		{ "FIRE", Color3.fromRGB(255, 90, 20), Color3.fromRGB(255, 200, 40) },
		{ "ICE", Color3.fromRGB(150, 230, 255), Color3.fromRGB(60, 120, 255) },
		{ "GOLD", Color3.fromRGB(255, 215, 80), Color3.fromRGB(255, 150, 20) },
		{ "TOXIC", Color3.fromRGB(80, 255, 120), Color3.fromRGB(20, 160, 60) },
		{ "ROSE", Color3.fromRGB(255, 110, 190), Color3.fromRGB(190, 80, 255) },
		{ "BLOOD", Color3.fromRGB(255, 40, 60), Color3.fromRGB(110, 0, 30) },
		{ "VOID", Color3.fromRGB(120, 60, 255), Color3.fromRGB(30, 10, 90) },
	}

	local PRESETS = {
		NORMAL = { walkOn = false, jumpOn = false, flySpeed = 60, slowFall = false, airCtl = false, sprint = false },
		RUNNER = { walkOn = true, walk = 40, jumpOn = true, jump = 65, flySpeed = 60, slowFall = false, airCtl = true, sprint = false },
		MOON = { walkOn = true, walk = 22, jumpOn = true, jump = 140, flySpeed = 60, slowFall = true, airCtl = true, sprint = false },
		SPEEDY = { walkOn = true, walk = 85, jumpOn = true, jump = 90, flySpeed = 90, slowFall = false, airCtl = true, sprint = false },
		FLYER = { walkOn = true, walk = 30, jumpOn = false, flySpeed = 110, slowFall = true, airCtl = true, sprint = false },
	}

	local function cam() return workspace.CurrentCamera end

	local function remote()
		return ReplicatedStorage:FindFirstChild("AAYAN_ADMIN_REMOTE")
	end

	local function fireServer(...)
		local r = remote()
		if r then
			local args = { ... }
			pcall(function() r:FireServer(unpack(args)) end)
			return true
		end
		return false
	end

	function F.captureDefaults()
		local h = getHum()
		if h then
			Def.walk = h.WalkSpeed
			Def.jump = h.JumpPower
			Def.useJP = h.UseJumpPower
		end
		Def.fov = cam() and cam().FieldOfView or 70
		Def.minZoom = player.CameraMinZoomDistance
		Def.maxZoom = player.CameraMaxZoomDistance
	end

	--------------------------------------------------------------------
	-- MOVEMENT
	--------------------------------------------------------------------

	function F.stopFly()
		if flyBV then flyBV:Destroy() flyBV = nil end
		if flyBG then flyBG:Destroy() flyBG = nil end
		local h = getHum()
		if h and not S.free then h.PlatformStand = false end
	end

	function F.setFly(on)
		S.fly = on
		if not on then F.stopFly() end
	end

	function F.restoreCollision()
		for part, v in pairs(origCollide) do
			if part.Parent then part.CanCollide = v end
		end
		origCollide = {}
	end

	function F.setNoclip(on)
		S.noclip = on
		if not on then F.restoreCollision() end
	end

	function F.restoreWalk()
		S.walkOn = false
		S.sprint = false
		walkApplied = false
		local h = getHum()
		if h then h.WalkSpeed = Def.walk end
	end

	function F.restoreJump()
		S.jumpOn = false
		jumpApplied = false
		local h = getHum()
		if h then
			h.JumpPower = Def.jump
			h.UseJumpPower = Def.useJP
		end
	end

	function F.setWalk(v)
		S.walk = v
		S.walkOn = true
		if S.serverMode then fireServer("walkspeed", v) end
	end

	function F.setJump(v)
		S.jump = v
		S.jumpOn = true
		if S.serverMode then fireServer("jumppower", v) end
	end

	function F.applyHum()
		local h = getHum()
		if not h then return end

		if S.free then
			if h.WalkSpeed ~= 0 then h.WalkSpeed = 0 end
			return
		end

		if S.walkOn or S.sprint then
			local w = (S.walkOn and S.walk or Def.walk) * (S.sprint and 1.6 or 1)
			if h.WalkSpeed ~= w then h.WalkSpeed = w end
			walkApplied = true
		elseif walkApplied then
			h.WalkSpeed = Def.walk
			walkApplied = false
		end

		if S.jumpOn then
			h.UseJumpPower = true
			if h.JumpPower ~= S.jump then h.JumpPower = S.jump end
			jumpApplied = true
		elseif jumpApplied then
			h.JumpPower = Def.jump
			h.UseJumpPower = Def.useJP
			jumpApplied = false
		end

		if h.AutoRotate ~= S.autoRotate and not S.fly then h.AutoRotate = S.autoRotate end
	end

	function F.dash()
		local root, h = getRoot(), getHum()
		if not root or not h then return end
		if os.clock() - lastDash < 0.8 then return end
		lastDash = os.clock()
		local dir = h.MoveDirection
		if dir.Magnitude < 0.1 then
			dir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		end
		dashDir = dir.Unit
		dashUntil = os.clock() + 0.16
		notify("DASH", nil, "on")
	end

	function F.setYaw(deg)
		S.yaw = deg
		local root = getRoot()
		if root then
			root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.rad(deg), 0)
		end
	end

	function F.flyStep()
		local root, h = getRoot(), getHum()
		if not (S.fly and root and h) then return end

		if not flyBV or flyBV.Parent ~= root then
			F.stopFly()
			flyBV = new("BodyVelocity", { Name = "AAYAN_FLY_BV", MaxForce = Vector3.new(1e9, 1e9, 1e9), Velocity = Vector3.zero }, root)
			flyBG = new("BodyGyro", { Name = "AAYAN_FLY_BG", MaxTorque = Vector3.new(1e9, 1e9, 1e9), P = 9000 }, root)
		end

		h.PlatformStand = true
		local c = cam()
		local look, right = c.CFrame.LookVector, c.CFrame.RightVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
		local rightFlat = Vector3.new(-flat.Z, 0, flat.X)

		local mv = h.MoveDirection
		local f = mv:Dot(flat)
		local s = mv:Dot(rightFlat)
		local vel

		if S.camRel then
			vel = look * f + right * s
		else
			vel = root.CFrame.LookVector * f + root.CFrame.RightVector * s
		end

		vel = vel * S.flySpeed
		if S.up then vel = vel + Vector3.new(0, S.flySpeed, 0) end
		if S.down then vel = vel - Vector3.new(0, S.flySpeed, 0) end

		flyBV.Velocity = vel
		flyBG.CFrame = CFrame.new(root.Position, root.Position + flat)
	end

	function F.moveStep(dt)
		local root, h = getRoot(), getHum()
		if not root or not h then return end
		if not S.fly then
			local vel = root.AssemblyLinearVelocity

			if S.airCtl and h.FloorMaterial == Enum.Material.Air and h.MoveDirection.Magnitude > 0.1 then
				local t = h.MoveDirection * math.max(h.WalkSpeed, 16)
				vel = Vector3.new(vel.X + (t.X - vel.X) * 0.12, vel.Y, vel.Z + (t.Z - vel.Z) * 0.12)
				root.AssemblyLinearVelocity = vel
			end

			if S.slowFall and vel.Y < -20 then
				root.AssemblyLinearVelocity = Vector3.new(vel.X, -20, vel.Z)
			end
		end

		if os.clock() < dashUntil then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = dashDir * S.dashPower + Vector3.new(0, v.Y, 0)
		end
	end

	function F.noclipStep()
		if not S.noclip then return end
		local c = getChar()
		if not c then return end
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide then
				origCollide[d] = true
				d.CanCollide = false
			end
		end
	end

	--------------------------------------------------------------------
	-- TELEPORT / WAYPOINTS
	--------------------------------------------------------------------

	function F.tp(cf, text)
		local root = getRoot()
		if not root then notify("Teleport", "No character", "warn") return end
		prevCF = root.CFrame
		ownMoveUntil = os.clock() + 0.6
		if S.serverMode and fireServer("teleport", cf.Position) then
			notify(text or "Teleport (server)", v3s(cf.Position))
			return
		end
		root.CFrame = cf
		root.AssemblyLinearVelocity = Vector3.zero
		notify(text or "Teleported", v3s(cf.Position))
	end

	function F.spawnPoint()
		local sp = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
		if sp then return sp.CFrame + Vector3.new(0, 4, 0) end
		return spawnCF
	end

	function F.rebuildWpList() end -- replaced once the UI exists

	function F.updateMarkers()
		if markerFolder then markerFolder:Destroy() markerFolder = nil end
		markerLabels = {}
		if not S.markers then return end
		markerFolder = new("Folder", { Name = "AAYAN_ADMIN_MARKERS" }, workspace)
		for i, w in ipairs(wps) do
			local p = new("Part", {
				Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
				Material = Enum.Material.Neon, Color = Theme.A1, Transparency = 0.45,
				Size = Vector3.new(0.6, 60, 0.6), CFrame = CFrame.new(w.cf.Position + Vector3.new(0, 30, 0)),
			}, markerFolder)
			local bb = new("BillboardGui", {
				Size = UDim2.fromOffset(120, 30), StudsOffset = Vector3.new(0, 34, 0), AlwaysOnTop = true, Adornee = p,
			}, p)
			local t = lbl(bb, w.name, 13, Color3.new(1, 1, 1), Enum.Font.GothamBlack, {
				Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3,
			})
			markerLabels[i] = { t = t, name = w.name, pos = w.cf.Position }
		end
	end

	function F.saveWp()
		local root = getRoot()
		if not root then notify("Waypoint", "No character", "warn") return end
		if #wps >= 20 then notify("Waypoint", "Limit of 20 reached", "warn") return end
		local n = #wps + 1
		wps[n] = { name = "WP " .. n, cf = root.CFrame }
		S.selWp = n
		F.rebuildWpList()
		F.updateMarkers()
		notify("Waypoint saved", wps[n].name .. "  " .. v3s(root.Position), "on")
	end

	function F.delWp(i)
		table.remove(wps, i)
		for k, w in ipairs(wps) do w.name = "WP " .. k end
		if S.selWp > #wps then S.selWp = #wps end
		F.rebuildWpList()
		F.updateMarkers()
	end

	function F.clearWps()
		wps = {}
		S.selWp = 0
		F.rebuildWpList()
		F.updateMarkers()
		notify("Waypoints cleared", nil, "off")
	end

	function F.tpWp(i)
		local w = wps[i]
		if not w then notify("Waypoint", "Nothing selected", "warn") return end
		F.tp(w.cf, "Teleport to " .. w.name)
	end

	function F.distToSel()
		local root = getRoot()
		local w = wps[S.selWp]
		if root and w then return (root.Position - w.cf.Position).Magnitude end
		return nil
	end

	function F.copyText(text, what)
		local fn = setclipboard or toclipboard or (Clipboard and Clipboard.set)
		if fn then
			local ok = pcall(fn, text)
			if ok then notify("Copied " .. what, text, "on") return end
		end
		notify("Clipboard not supported", text, "warn")
	end

	--------------------------------------------------------------------
	-- CAMERA
	--------------------------------------------------------------------

	function F.setFov(v)
		S.fov = v
		S.fovOn = true
		if cam() then cam().FieldOfView = v end
	end

	function F.setSens(v)
		S.sens = v
		pcall(function() UserSettings():GetService("UserGameSettings").MouseSensitivity = v end)
	end

	function F.setLock(on)
		S.lock = on
		local c = cam()
		if on then
			if S.free then F.setFree(false) end
			lockCF = c.CFrame
			c.CameraType = Enum.CameraType.Scriptable
		elseif not S.free then
			c.CameraType = Enum.CameraType.Custom
		end
	end

	function F.setSmooth(on)
		S.smooth = on
		smoothCF = cam() and cam().CFrame or nil
	end

	function F.setFree(on)
		local c = cam()
		if on then
			if S.lock then S.lock = false end
			S.free = true
			local cf = c.CFrame
			fc.pos = cf.Position
			local lv = cf.LookVector
			fc.yaw = math.atan2(-lv.X, -lv.Z)
			fc.pitch = math.asin(math.clamp(lv.Y, -1, 1))
			c.CameraType = Enum.CameraType.Scriptable
			F.stopFly()
		else
			S.free = false
			c.CameraType = Enum.CameraType.Custom
			local h = getHum()
			if h then c.CameraSubject = h end
			walkApplied = true -- restore the real walk speed on the next apply
			local hh = getHum()
			if hh then hh.WalkSpeed = Def.walk end
		end
	end

	function F.freeStep(dt)
		if not S.free then return end
		local c = cam()
		local h = getHum()
		local rot = CFrame.Angles(0, fc.yaw, 0) * CFrame.Angles(fc.pitch, 0, 0)
		local move = Vector3.zero
		if h then
			local lv = rot:VectorToObjectSpace(h.MoveDirection)
			move = Vector3.new(lv.X, 0, lv.Z)
		end
		if UIS:IsKeyDown(Enum.KeyCode.W) then move = move + Vector3.new(0, 0, -1) end
		if UIS:IsKeyDown(Enum.KeyCode.S) then move = move + Vector3.new(0, 0, 1) end
		if UIS:IsKeyDown(Enum.KeyCode.A) then move = move + Vector3.new(-1, 0, 0) end
		if UIS:IsKeyDown(Enum.KeyCode.D) then move = move + Vector3.new(1, 0, 0) end
		local vert = 0
		if S.up or UIS:IsKeyDown(Enum.KeyCode.E) then vert = vert + 1 end
		if S.down or UIS:IsKeyDown(Enum.KeyCode.Q) then vert = vert - 1 end
		local speed = (UIS:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1) * 40
		fc.pos = fc.pos + rot:VectorToWorldSpace(move) * speed * dt + Vector3.new(0, vert * speed * dt, 0)
		c.CFrame = CFrame.new(fc.pos) * rot
	end

	function F.zoomTo(target)
		target = math.clamp(target, 0.5, 400)
		player.CameraMinZoomDistance = target
		player.CameraMaxZoomDistance = target
		task.delay(0.35, function()
			if alive then
				player.CameraMinZoomDistance = Def.minZoom
				player.CameraMaxZoomDistance = math.max(Def.maxZoom, target)
			end
		end)
	end

	function F.zoomBy(delta)
		local c = cam()
		local root = getRoot()
		local focus = root and root.Position or c.Focus.Position
		F.zoomTo((c.CFrame.Position - focus).Magnitude + delta)
	end

	function F.setFirst(on)
		player.CameraMode = on and Enum.CameraMode.LockFirstPerson or Enum.CameraMode.Classic
	end

	function F.thirdPerson()
		player.CameraMode = Enum.CameraMode.Classic
		F.zoomTo(12)
	end

	function F.resetCamera()
		if S.free then F.setFree(false) end
		S.lock, S.smooth, S.fovOn = false, false, false
		local c = cam()
		c.CameraType = Enum.CameraType.Custom
		local h = getHum()
		if h then c.CameraSubject = h end
		c.FieldOfView = Def.fov
		S.fov = Def.fov
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMinZoomDistance = Def.minZoom
		player.CameraMaxZoomDistance = Def.maxZoom
		F.setSens(Def.sens)
		S.sens = Def.sens
		spectating = nil
	end

	function F.spectate(name)
		local q = (name or ""):lower()
		if q == "" then notify("Spectate", "Type a player name", "warn") return end
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and (p.Name:lower():find(q, 1, true) or p.DisplayName:lower():find(q, 1, true)) then
				local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				if h then
					cam().CameraSubject = h
					spectating = p
					notify("Spectating", p.DisplayName, "on")
					return
				end
			end
		end
		notify("Spectate", "Player not found", "warn")
	end

	function F.stopSpectate()
		spectating = nil
		local h = getHum()
		if h then cam().CameraSubject = h end
	end

	--------------------------------------------------------------------
	-- VISUALS
	--------------------------------------------------------------------

	function F.restoreLook()
		for part, o in pairs(origLook) do
			if part.Parent then
				part.Material = o.m
				part.Color = o.c
			end
		end
		origLook = {}
	end

	function F.destroyFx()
		for _, o in ipairs(fxObjs) do pcall(function() o:Destroy() end) end
		fxObjs = {}
	end

	function F.clearFx()
		S.aura, S.particles, S.trail, S.neon = false, false, false, false
		F.destroyFx()
		F.restoreLook()
	end

	function F.rebuildFx()
		F.destroyFx()
		local c, root = getChar(), getRoot()
		if not c or not root then return end
		local a = AURAS[S.auraIdx]
		local perf = S.perf and 0.3 or 1

		if S.aura then
			fxObjs[#fxObjs + 1] = new("Highlight", {
				Name = "AAYAN_AURA", Adornee = c, FillColor = a[2], OutlineColor = a[3],
				FillTransparency = 0.95 - 0.5 * S.fx, OutlineTransparency = 0.3,
				DepthMode = Enum.HighlightDepthMode.Occluded,
			}, c)
		end

		if S.particles or S.aura then
			local at = new("Attachment", { Name = "AAYAN_FXA", Position = Vector3.new(0, -1, 0) }, root)
			fxObjs[#fxObjs + 1] = at
			fxObjs[#fxObjs + 1] = new("ParticleEmitter", {
				Name = "AAYAN_PARTS", Texture = "rbxasset://textures/particles/sparkles_main.dds",
				Rate = (S.particles and (10 + 60 * S.fx) or (4 + 14 * S.fx)) * perf,
				Lifetime = NumberRange.new(0.8, 1.6), Speed = NumberRange.new(1, 4),
				SpreadAngle = Vector2.new(180, 180), LightEmission = 1, LightInfluence = 0,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
				Color = ColorSequence.new(a[2], a[3]),
			}, at)
		end

		if S.trail then
			local a0 = new("Attachment", { Name = "AAYAN_T0", Position = Vector3.new(0, 1.2, 0) }, root)
			local a1 = new("Attachment", { Name = "AAYAN_T1", Position = Vector3.new(0, -1.6, 0) }, root)
			fxObjs[#fxObjs + 1] = a0
			fxObjs[#fxObjs + 1] = a1
			fxObjs[#fxObjs + 1] = new("Trail", {
				Name = "AAYAN_TRAIL", Attachment0 = a0, Attachment1 = a1, Lifetime = 0.7 * (S.perf and 0.5 or 1),
				LightEmission = 1, Color = ColorSequence.new(a[2], a[3]),
				Transparency = NumberSequence.new(0.1, 1), WidthScale = NumberSequence.new(1, 0),
			}, root)
		end

		F.restoreLook()
		if S.neon then
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
					origLook[d] = { m = d.Material, c = d.Color }
					d.Material = Enum.Material.Neon
					d.Color = a[2]
				end
			end
		end
	end

	function F.updateFx()
		for _, o in ipairs(fxObjs) do
			if o:IsA("Highlight") then
				o.FillTransparency = 0.95 - 0.5 * S.fx
			elseif o:IsA("ParticleEmitter") then
				local perf = S.perf and 0.3 or 1
				o.Rate = (S.particles and (10 + 60 * S.fx) or (4 + 14 * S.fx)) * perf
			end
		end
	end

	function F.emote(name)
		local h = getHum()
		if not h then return end
		local ok, res = pcall(function() return h:PlayEmote(name) end)
		if ok and res then
			notify("Emote: " .. name, nil, "on")
		else
			notify("Emote unavailable", "Needs R15 + default animations", "warn")
		end
	end

	function F.stopEmote()
		local h = getHum()
		local an = h and h:FindFirstChildOfClass("Animator")
		if an then
			for _, t in ipairs(an:GetPlayingAnimationTracks()) do t:Stop() end
		end
	end

	--------------------------------------------------------------------
	-- PRESETS / RESETS
	--------------------------------------------------------------------

	local function applyTable(t)
		for k, v in pairs(t) do S[k] = v end
		if t.fov ~= nil and S.fovOn and cam() then cam().FieldOfView = S.fov end
		F.applyHum()
	end

	function F.applyPreset(name)
		local p = PRESETS[name]
		if not p then return end
		applyTable(p)
		notify("Preset: " .. name, nil, "on")
	end

	function F.saveTemp()
		savedPreset = {
			walkOn = S.walkOn, walk = S.walk, jumpOn = S.jumpOn, jump = S.jump, flySpeed = S.flySpeed,
			fovOn = S.fovOn, fov = S.fov, slowFall = S.slowFall, airCtl = S.airCtl, sprint = S.sprint,
		}
		notify("Settings saved", "Memory only (lost on rejoin)", "on")
	end

	function F.loadTemp()
		if not savedPreset then notify("Load settings", "Nothing saved yet", "warn") return end
		applyTable(savedPreset)
		notify("Settings loaded", nil, "on")
	end

	function F.stopAll()
		F.setFly(false)
		F.setNoclip(false)
		S.infJump, S.airCtl, S.slowFall, S.sprint = false, false, false, false
		S.up, S.down = false, false
		dashUntil = 0
		if S.free then F.setFree(false) end
		if S.lock then F.setLock(false) end
		S.smooth = false
		F.stopSpectate()
		F.restoreWalk()
		F.restoreJump()
		local h = getHum()
		if h then
			h.PlatformStand = false
			h.AutoRotate = true
		end
		S.autoRotate = true
		notify("STOP ALL", "Movement effects disabled", "off")
	end

	function F.restoreDefaults()
		F.restoreWalk()
		F.restoreJump()
		F.restoreCollision()
		F.resetCamera()
		local h = getHum()
		if h then h.AutoRotate = true end
		S.autoRotate = true
		notify("Defaults restored", "Walk / jump / camera / collision", "on")
	end

	function F.emergency()
		F.stopAll()
		F.restoreDefaults()
		F.clearFx()
		F.allShields(false)
		F.weatherStop()
		S.markers, S.navigate = false, false
		F.updateMarkers()
		local r = getRoot()
		if r then r.AssemblyLinearVelocity = Vector3.zero end
		notify("EMERGENCY RESET", "Everything local was reverted", "warn")
	end

	function F.status()
		local t = {}
		if S.fly then t[#t + 1] = "FLY" end
		if S.noclip then t[#t + 1] = "NOCLIP" end
		if S.walkOn then t[#t + 1] = "WALK " .. fmt0(S.walk) end
		if S.jumpOn then t[#t + 1] = "JUMP " .. fmt0(S.jump) end
		if S.sprint then t[#t + 1] = "SPRINT" end
		if S.infJump then t[#t + 1] = "INFJUMP" end
		if S.airCtl then t[#t + 1] = "AIR" end
		if S.slowFall then t[#t + 1] = "SLOWFALL" end
		if S.free then t[#t + 1] = "FREECAM" end
		if S.lock then t[#t + 1] = "CAMLOCK" end
		if S.smooth then t[#t + 1] = "SMOOTH" end
		if spectating then t[#t + 1] = "SPECTATE" end
		return t
	end


	--==============================================
	-- SHIELDS (30)  -  all local / defensive, they only protect YOUR character
	--==============================================

	do
		local shTimers = { scan = 0, slow = 0, prox = 0, heal = 0, other = 0, att = 0 }
		local lastPos, lastVel, lastSafeCF
		local origTouch = {}
		local applied = {}
		local attachTimers = {}
		local alerted = {}
		local lastDodge, lastPanic, lastAttach, lastNote = 0, 0, 0, 0
		local lastHealth
		local bubble

		F.SHIELDS = {
			-- group 1: fling & physics
			{ "antiFling", "Anti-Fling (speed clamp)", "Fling & Physics" },
			{ "antiSkyFling", "Anti-Sky-Fling (up launch)", "Fling & Physics" },
			{ "antiSpin", "Anti-Spin (rotation clamp)", "Fling & Physics" },
			{ "antiKnockback", "Anti-Knockback", "Fling & Physics" },
			{ "playerNoCollide", "Player No-Collide (can't be pushed)", "Fling & Physics" },
			{ "antiBodyMover", "Anti-BodyMover / Force on me", "Fling & Physics" },
			-- group 2: attach / bang / grab
			{ "antiAttach", "Anti-Bang / Anti-Attach (auto step away)", "Anti-Attach" },
			{ "antiWeld", "Anti-Weld / Grab (cut foreign welds)", "Anti-Attach" },
			{ "autoDodge", "Auto-Dodge fast players", "Anti-Attach" },
			{ "proximityAlert", "Proximity alert (players too close)", "Anti-Attach" },
			{ "antiTouch", "Anti-Touch (CanTouch off)", "Anti-Attach" },
			-- group 3: character protection
			{ "antiSit", "Anti-Sit", "Character Protection" },
			{ "noSeated", "Disable Seated state", "Character Protection" },
			{ "antiRagdoll", "Anti-Ragdoll / Fall-down", "Character Protection" },
			{ "antiStun", "Anti-Stun (PlatformStand off)", "Character Protection" },
			{ "antiFreeze", "Anti-Freeze (unanchor root)", "Character Protection" },
			{ "antiTeleport", "Anti-Teleport (snap back)", "Character Protection" },
			{ "antiVoid", "Anti-Void (safe return)", "Character Protection" },
			{ "antiSlow", "Anti-Slow (restore walk speed)", "Character Protection" },
			{ "antiJumpLock", "Anti-Jump-Lock", "Character Protection" },
			{ "healthLock", "Health lock (visual)", "Character Protection" },
			{ "autoHeal", "Auto-Heal", "Character Protection" },
			{ "panicTP", "Panic teleport at low health", "Character Protection" },
			{ "shieldBubble", "Shield bubble (visual)", "Character Protection" },
			-- group 4: screen & misc
			{ "antiBlur", "Anti-Blur / Screen-Flash", "Screen & Misc" },
			{ "antiCamHijack", "Anti-Camera-Hijack", "Screen & Misc" },
			{ "antiAudioSpam", "Anti-Audio-Spam (loud sounds)", "Screen & Misc" },
			{ "antiForeignGui", "Anti-Foreign-GUI on my character", "Screen & Misc" },
			{ "antiParticles", "Anti-Fire / Smoke / Particles on me", "Screen & Misc" },
			{ "antiAFK", "Anti-AFK", "Screen & Misc" },
		}

		local function count()
			local n = 0
			for _, d in ipairs(F.SHIELDS) do if Sh[d[1]] then n = n + 1 end end
			return n
		end
		F.shieldCount = count

		local function buildBubble()
			if bubble then bubble:Destroy() bubble = nil end
			if not Sh.shieldBubble then return end
			local c, root = getChar(), getRoot()
			if not c or not root then return end
			bubble = new("Part", {
				Name = "AAYAN_BUBBLE", Shape = Enum.PartType.Ball, Size = Vector3.new(9, 9, 9),
				Material = Enum.Material.Neon, Color = Theme.A1, Transparency = 0.88,
				CanCollide = false, CanTouch = false, CanQuery = false, Massless = true, CastShadow = false,
				CFrame = root.CFrame,
			}, c)
			new("WeldConstraint", { Part0 = root, Part1 = bubble }, bubble)
		end

		local function restoreTouch()
			for part, v in pairs(origTouch) do
				if part.Parent then part.CanTouch = v end
			end
			origTouch = {}
		end

		function F.setShield(id, v)
			Sh[id] = v and true or nil
			if id == "antiTouch" and not v then restoreTouch() end
			if id == "shieldBubble" then buildBubble() end
			if id == "noSeated" or id == "antiRagdoll" then applied = {} end
			if id == "antiBlur" or id == "antiCamHijack" then shTimers.slow = 9 end
		end

		function F.allShields(on)
			for _, d in ipairs(F.SHIELDS) do F.setShield(d[1], on) end
			notify(on and "ALL SHIELDS ON" or "ALL SHIELDS OFF", count() .. " / 30 active", on and "on" or "off")
		end

		function F.recommendedShields()
			for _, id in ipairs({ "antiFling", "antiSkyFling", "antiSpin", "playerNoCollide", "antiBodyMover",
				"antiAttach", "antiWeld", "antiSit", "antiRagdoll", "antiStun", "antiFreeze", "antiVoid", "antiBlur" }) do
				F.setShield(id, true)
			end
			notify("Recommended shields ON", count() .. " / 30 active", "on")
		end

		function F.shieldReset()
			lastPos, lastVel, lastSafeCF, lastHealth = nil, nil, nil, nil
			applied = {}
			origTouch = {}
			attachTimers = {}
			bubble = nil
			buildBubble()
		end

		function F.shieldShutdown()
			restoreTouch()
			if bubble then bubble:Destroy() bubble = nil end
			local h = getHum()
			if h then
				pcall(function()
					h:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
					h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
					h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
				end)
			end
		end

		local function note(title, sub)
			if os.clock() - lastNote > 2 then
				lastNote = os.clock()
				notify(title, sub, "warn")
			end
		end

		local function otherRoots()
			local list = {}
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and p.Character then
					local r = p.Character:FindFirstChild("HumanoidRootPart")
					if r then list[#list + 1] = { p = p, r = r } end
				end
			end
			return list
		end

		local function stepAway(root, from, dist)
			local dir = root.Position - from
			dir = Vector3.new(dir.X, 0, dir.Z)
			dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(1, 0, 0)
			ownMoveUntil = os.clock() + 0.6
			root.CFrame = root.CFrame + dir * dist + Vector3.new(0, 1, 0)
			root.AssemblyLinearVelocity = Vector3.zero
		end

		local function isMine(d)
			return d.Name:sub(1, 5) == "AAYAN"
		end

		local MOVERS = { "BodyMover", "LinearVelocity", "AngularVelocity", "VectorForce", "AlignPosition", "AlignOrientation", "Torque" }
		local function isMover(d)
			for _, c in ipairs(MOVERS) do
				if d:IsA(c) then return true end
			end
			return false
		end

		function F.shieldStep(dt)
			if next(Sh) == nil then return end
			local c, h, root = getChar(), getHum(), getRoot()
			if not (c and h and root) then return end

			local now = os.clock()
			local selfMoving = S.fly or S.free or now < dashUntil or now < ownMoveUntil
			local vel = root.AssemblyLinearVelocity
			local walkNow = (S.walkOn and S.walk or Def.walk) * (S.sprint and 1.6 or 1)

			-- 1 anti fling (horizontal) ------------------------------------------------------------------
			if Sh.antiFling and not selfMoving then
				local hv = Vector3.new(vel.X, 0, vel.Z)
				if hv.Magnitude > math.max(120, walkNow * 3.5) then
					root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
					vel = root.AssemblyLinearVelocity
					note("Anti-Fling", "Fling blocked")
				end
			end

			-- 2 sky fling ------------------------------------------------------------------------------------
			if Sh.antiSkyFling and not selfMoving then
				local lim = math.max(110, (S.jumpOn and S.jump or Def.jump) * 1.4)
				if vel.Y > lim then
					root.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
					vel = root.AssemblyLinearVelocity
					note("Anti-Sky-Fling", "Launch blocked")
				end
			end

			-- 3 spin ---------------------------------------------------------------------------------------------
			if Sh.antiSpin and not selfMoving and root.AssemblyAngularVelocity.Magnitude > 25 then
				root.AssemblyAngularVelocity = Vector3.zero
			end

			-- 4 knockback --------------------------------------------------------------------------------------
			if Sh.antiKnockback and lastVel and not selfMoving and dt < 0.1 then
				local dv = Vector3.new(vel.X - lastVel.X, 0, vel.Z - lastVel.Z)
				if dv.Magnitude > math.max(60, walkNow * 1.6) then
					root.AssemblyLinearVelocity = Vector3.new(lastVel.X, vel.Y, lastVel.Z)
					vel = root.AssemblyLinearVelocity
				end
			end
			lastVel = vel

			-- anti teleport ------------------------------------------------------------------------------------
			if Sh.antiTeleport and lastPos and not selfMoving and dt < 0.1 and (root.Position - lastPos).Magnitude > 50 then
				root.CFrame = CFrame.new(lastPos) * (root.CFrame - root.CFrame.Position)
				root.AssemblyLinearVelocity = Vector3.zero
				note("Anti-Teleport", "Teleport reverted")
			else
				lastPos = root.Position
			end

			-- anti sit / seated ------------------------------------------------------------------------------
			if Sh.antiSit and h.Sit then h.Sit = false end
			local wantNoSeat = Sh.noSeated == true
			if applied.seated ~= wantNoSeat then
				pcall(function() h:SetStateEnabled(Enum.HumanoidStateType.Seated, not wantNoSeat) end)
				applied.seated = wantNoSeat
			end

			-- ragdoll ---------------------------------------------------------------------------------------------
			local wantNoRag = Sh.antiRagdoll == true
			if applied.rag ~= wantNoRag then
				pcall(function()
					h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not wantNoRag)
					h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not wantNoRag)
				end)
				applied.rag = wantNoRag
			end
			if wantNoRag then
				local st = h:GetState()
				if st == Enum.HumanoidStateType.FallingDown or st == Enum.HumanoidStateType.Ragdoll then
					h:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end

			-- stun / freeze --------------------------------------------------------------------------------------
			if Sh.antiStun and h.PlatformStand and not S.fly and not S.free then h.PlatformStand = false end
			if Sh.antiFreeze and root.Anchored and not S.free then root.Anchored = false end

			-- walk / jump locks ------------------------------------------------------------------------------
			if Sh.antiSlow and not S.free and h.WalkSpeed < walkNow * 0.9 and Def.walk > 0 then
				h.WalkSpeed = walkNow
			end
			if Sh.antiJumpLock and not S.free and h.JumpPower < 1 and Def.jump > 0 then
				h.UseJumpPower = true
				h.JumpPower = S.jumpOn and S.jump or Def.jump
			end

			-- health ------------------------------------------------------------------------------------------------
			if Sh.healthLock then
				if lastHealth and h.Health > 0 and h.Health < lastHealth then h.Health = lastHealth end
				lastHealth = h.Health
			else
				lastHealth = nil
			end

			-- safe position tracking (void + panic) -------------------------------------------------------
			if (Sh.antiVoid or Sh.panicTP) and h.FloorMaterial ~= Enum.Material.Air then
				if root.Position.Y > workspace.FallenPartsDestroyHeight + 120 then
					lastSafeCF = root.CFrame
				end
			end
			if Sh.antiVoid and lastSafeCF and root.Position.Y < workspace.FallenPartsDestroyHeight + 70 then
				ownMoveUntil = now + 0.6
				root.AssemblyLinearVelocity = Vector3.zero
				root.CFrame = lastSafeCF + Vector3.new(0, 5, 0)
				note("Anti-Void", "Returned to safe ground")
			end
			if Sh.panicTP and h.Health > 0 and h.Health < h.MaxHealth * 0.3 and now - lastPanic > 8 then
				local cf = lastSafeCF or F.spawnPoint()
				if cf then
					lastPanic = now
					ownMoveUntil = now + 0.6
					root.CFrame = cf + Vector3.new(0, 4, 0)
					note("Panic teleport", "Low health - moved to safe spot")
				end
			end

			-- auto heal ----------------------------------------------------------------------------------------------
			if Sh.autoHeal then
				shTimers.heal = shTimers.heal + dt
				if shTimers.heal > 0.5 then
					shTimers.heal = 0
					if h.Health > 0 and h.Health < h.MaxHealth then h.Health = math.min(h.MaxHealth, h.Health + 3) end
				end
			end

			-- other players: attach / dodge / proximity (every 0.15s) ---------------------------------------
			if Sh.antiAttach or Sh.autoDodge or Sh.proximityAlert then
				shTimers.att = shTimers.att + dt
				if shTimers.att > 0.15 then
					local step = shTimers.att
					shTimers.att = 0
					for _, o in ipairs(otherRoots()) do
						local off = o.r.Position - root.Position
						local d = off.Magnitude

						if Sh.antiAttach then
							if d < 3.3 and not selfMoving then
								attachTimers[o.p] = (attachTimers[o.p] or 0) + step
								if attachTimers[o.p] > 1.0 and now - lastAttach > 2 then
									attachTimers[o.p] = 0
									lastAttach = now
									stepAway(root, o.r.Position, 11)
									note("Anti-Attach", o.p.DisplayName .. " was stuck to you - moved away")
								end
							else
								attachTimers[o.p] = 0
							end
						end

						if Sh.autoDodge and d < 13 and now - lastDodge > 1 then
							local ov = o.r.AssemblyLinearVelocity
							if ov.Magnitude > 85 and ov:Dot(-off.Unit) > 60 then
								lastDodge = now
								local side = off:Cross(Vector3.new(0, 1, 0))
								side = side.Magnitude > 0.1 and side.Unit or Vector3.new(1, 0, 0)
								ownMoveUntil = now + 0.6
								root.CFrame = root.CFrame + side * 12
								note("Auto-Dodge", o.p.DisplayName .. " came at you fast")
							end
						end

						if Sh.proximityAlert and d < 9 and (not alerted[o.p] or now - alerted[o.p] > 8) then
							alerted[o.p] = now
							notify("Proximity alert", o.p.DisplayName .. "  " .. fmt0(d) .. " studs", "warn")
						end
					end
				end
			end

			-- scans (0.4s): foreign movers / welds / guis / particles --------------------------------------
			shTimers.scan = shTimers.scan + dt
			if shTimers.scan > 0.4 then
				shTimers.scan = 0

				if Sh.antiBodyMover or Sh.antiForeignGui or Sh.antiParticles or Sh.antiWeld then
					for _, d in ipairs(c:GetDescendants()) do
						if not isMine(d) then
							if Sh.antiBodyMover and isMover(d) then
								d:Destroy()
							elseif Sh.antiWeld and (d:IsA("WeldConstraint") or d:IsA("Weld")) then
								local p0, p1 = d.Part0, d.Part1
								if (p0 and not p0:IsDescendantOf(c)) or (p1 and not p1:IsDescendantOf(c)) then d:Destroy() end
							elseif Sh.antiForeignGui and (d:IsA("BillboardGui") or d:IsA("SurfaceGui")) then
								d:Destroy()
							elseif Sh.antiParticles and (d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles")) then
								d:Destroy()
							end
						end
					end
				end
			end

			-- foreign constraints living in OTHER characters but tied to me (every 0.6s) ------------------
			if Sh.antiWeld or Sh.antiBodyMover then
				shTimers.other = shTimers.other + dt
				if shTimers.other > 0.6 then
					shTimers.other = 0
					for _, p in ipairs(Players:GetPlayers()) do
						if p ~= player and p.Character then
							for _, d in ipairs(p.Character:GetDescendants()) do
								if d:IsA("Weld") or d:IsA("WeldConstraint") then
									local p0, p1 = d.Part0, d.Part1
									if Sh.antiWeld and ((p0 and p0:IsDescendantOf(c)) or (p1 and p1:IsDescendantOf(c))) then
										d:Destroy()
										note("Anti-Weld", "Cut a weld from " .. p.DisplayName)
									end
								elseif d:IsA("Constraint") and Sh.antiWeld then
									local a0, a1 = d.Attachment0, d.Attachment1
									if (a0 and a0:IsDescendantOf(c)) or (a1 and a1:IsDescendantOf(c)) then
										d:Destroy()
										note("Anti-Grab", "Cut a constraint from " .. p.DisplayName)
									end
								end
							end
						end
					end
				end
			end

			-- slow scans (1s): touch, blur, camera, audio ---------------------------------------------------
			shTimers.slow = shTimers.slow + dt
			if shTimers.slow > 1 then
				shTimers.slow = 0

				if Sh.antiTouch then
					for _, d in ipairs(c:GetDescendants()) do
						if d:IsA("BasePart") and d.CanTouch then
							origTouch[d] = true
							d.CanTouch = false
						end
					end
				end

				if Sh.antiBlur then
					for _, d in ipairs(Lighting:GetChildren()) do
						if not isMine(d) and (d:IsA("BlurEffect") or d:IsA("ColorCorrectionEffect") or d:IsA("DepthOfFieldEffect")) then
							d:Destroy()
						end
					end
					local cm = workspace.CurrentCamera
					if cm then
						for _, d in ipairs(cm:GetChildren()) do
							if not isMine(d) and (d:IsA("BlurEffect") or d:IsA("ColorCorrectionEffect")) then d:Destroy() end
						end
					end
				end

				if Sh.antiCamHijack and not S.free and not S.lock and not spectating then
					local cm = workspace.CurrentCamera
					if cm then
						if cm.CameraType ~= Enum.CameraType.Custom then cm.CameraType = Enum.CameraType.Custom end
						if cm.CameraSubject ~= h then cm.CameraSubject = h end
					end
				end

				if Sh.antiAudioSpam then
					local n = 0
					for _, d in ipairs(workspace:GetDescendants()) do
						if d:IsA("Sound") and d.IsPlaying and d.Volume > 6 then d.Volume = 1 end
						n = n + 1
						if n > 1500 then break end
					end
				end
			end
		end

		function F.shieldStepped()
			if Sh.playerNoCollide then
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= player and p.Character then
						for _, d in ipairs(p.Character:GetChildren()) do
							if d:IsA("BasePart") and d.CanCollide then d.CanCollide = false end
						end
					end
				end
			end
		end
	end

	--==============================================
	-- WEATHER & SKY (13 modes that stay on until you stop them)
	--==============================================

	do
		local THUNDER_ID = "rbxassetid://130457325001606"
		local RED_MOON_SOUND_ID = "rbxassetid://1844701455"
		local PEACE_SOUND_ID = "rbxassetid://1847702709"
		local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
		local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

		local Original = nil
		local stashed, tracked = {}, {}
		local modeUpdate = nil
		local desired, mine = nil, {}
		local envFolder = nil

		local function mk(class, props, parent)
			local o = Instance.new(class)
			for k, v in pairs(props) do o[k] = v end
			if parent then o.Parent = parent end
			return o
		end
		local function track(inst) tracked[#tracked + 1] = inst return inst end
		local function setLight(t) for k, v in pairs(t) do Lighting[k] = v end end
		local function camPos()
			local c = workspace.CurrentCamera
			return c and c.CFrame.Position or Vector3.new(0, 0, 0)
		end
		local function stashSkyAtmos()
			for _, v in ipairs(Lighting:GetChildren()) do
				if (v:IsA("Sky") or v:IsA("Atmosphere")) and v.Name:sub(1, 6) ~= "AAYAN_" then
					stashed[#stashed + 1] = v
					v.Parent = nil
				end
			end
		end
		local function circle(parent, sx, sy, color, transp, ax, ay)
			local f = mk("Frame", {
				BackgroundColor3 = color, BackgroundTransparency = transp, BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(ax or 0.5, ay or 0.5), Size = UDim2.fromScale(sx, sy),
			}, parent)
			mk("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
			return f
		end
		local function emitterPart(name, size)
			return mk("Part", {
				Name = name, Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
				Transparency = 1, Size = size,
			}, envFolder)
		end
		local function fade(maxValue)
			return NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, maxValue),
				NumberSequenceKeypoint.new(0.8, maxValue), NumberSequenceKeypoint.new(1, 1),
			})
		end
		local function bubble(a, b)
			return NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, a, b or 0), NumberSequenceKeypoint.new(1, 0),
			})
		end
		local function highlightChar(fill, fillT, outline, outT)
			local char = getChar()
			if not char then return nil end
			return track(mk("Highlight", {
				Name = "AAYAN_WGLOW", Adornee = char, FillColor = fill, FillTransparency = fillT,
				OutlineColor = outline, OutlineTransparency = outT, DepthMode = Enum.HighlightDepthMode.Occluded,
			}, char))
		end
		local function modeSound(id, volume)
			local s = mk("Sound", { Name = "AAYAN_MODE_SOUND", SoundId = id, Volume = volume, Looped = true }, sg)
			track(s)
			s:Play()
			return s
		end
		local function getRootW() return getRoot() end

		local Modes = {}

		-- DARK WEATHER (unchanged look) ---------------------------------------------

		Modes.dark = function()

			setLight{
				ClockTime = 0,
				Brightness = .35,
				Ambient = Color3.fromRGB(7,7,15),
				OutdoorAmbient = Color3.fromRGB(10,10,20),
				FogStart = 8,
				FogEnd = 155,
				ExposureCompensation = -.15,
			}

			mk("Atmosphere", {
				Name = "AAYAN_DARK_ATMOSPHERE",
				Density = .30, Offset = .05, Haze = 1.8, Glare = 0,
				Color = Color3.fromRGB(20,20,38),
				Decay = Color3.fromRGB(3,3,10),
			}, Lighting)

			mk("ColorCorrectionEffect", {
				Name = "AAYAN_DARK_GLOW",
				Brightness = -.04, Contrast = .12, Saturation = -.05,
				TintColor = Color3.fromRGB(185,195,225),
			}, Lighting)
		end

		-- RED MOON (big glowing moon, craters, drifting clouds, embers) ---------------

		Modes.moon = function()

			stashSkyAtmos()

			setLight{
				ClockTime = 0,
				Brightness = .4,
				Ambient = Color3.fromRGB(35,4,7),
				OutdoorAmbient = Color3.fromRGB(55,7,10),
				FogStart = 10,
				FogEnd = 260,
				FogColor = Color3.fromRGB(60,8,12),
			}

			mk("Sky", { Name = "AAYAN_RED_SKY", StarCount = 1800, CelestialBodiesShown = false }, Lighting)

			mk("Atmosphere", {
				Name = "AAYAN_RED_ATMOSPHERE",
				Density = .23, Offset = 0, Haze = 1.2, Glare = .15,
				Color = Color3.fromRGB(170,25,25),
				Decay = Color3.fromRGB(45,3,6),
			}, Lighting)

			mk("ColorCorrectionEffect", {
				Name = "AAYAN_RED_GLOW",
				TintColor = Color3.fromRGB(255,170,170),
				Brightness = -.03, Contrast = .1, Saturation = .05,
			}, Lighting)

			mk("BloomEffect", { Name = "AAYAN_RED_BLOOM", Intensity = .35, Size = 28, Threshold = .9 }, Lighting)

			local anchor = emitterPart("AAYAN_RED_MOON", Vector3.new(1,1,1))

			local bb = mk("BillboardGui", {
				Size = UDim2.new(70,0,70,0),
				AlwaysOnTop = false,
				LightInfluence = 0,
				ResetOnSpawn = false,
				Adornee = anchor,
			}, anchor)

			local halos = {}
			for i,v in ipairs({ {1.0,.93}, {.78,.88}, {.62,.80} }) do
				halos[i] = { f = circle(bb, v[1], v[1], Color3.fromRGB(255,30,25), v[2]), base = v[2] }
			end

			local disc = circle(bb, .46, .46, Color3.new(1,1,1), 0)
			disc.ClipsDescendants = true
			mk("UIGradient", {
				Color = ColorSequence.new(Color3.fromRGB(255,125,85), Color3.fromRGB(135,12,18)),
				Rotation = 50,
			}, disc)
			mk("UIStroke", { Color = Color3.fromRGB(255,150,110), Thickness = 2, Transparency = .35 }, disc)

			for _,c in ipairs({
				{.30,.35,.16}, {.62,.28,.10}, {.56,.64,.20},
				{.25,.68,.08}, {.78,.52,.07}, {.43,.16,.06},
			}) do
				circle(disc, c[3], c[3], Color3.fromRGB(95,6,10), .55, c[1], c[2])
			end

			local clouds = {}
			for i,y in ipairs({ .36, .62 }) do
				local cl = mk("Frame", {
					BackgroundColor3 = Color3.fromRGB(70,4,8),
					BackgroundTransparency = .55,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(.5,.5),
					Position = UDim2.fromScale(.5, y),
					Size = UDim2.fromScale(.55, .08),
				}, disc)
				mk("UICorner", { CornerRadius = UDim.new(1,0) }, cl)
				clouds[i] = { f = cl, y = y, phase = i * 2.1 }
			end

			-- drifting embers around the player
			local embers = emitterPart("AAYAN_EMBERS", Vector3.new(90,1,90))
			mk("ParticleEmitter", {
				Texture = SPARK,
				Rate = 22,
				Lifetime = NumberRange.new(5,8),
				Speed = NumberRange.new(1,3),
				Acceleration = Vector3.new(0,1.5,0),
				SpreadAngle = Vector2.new(35,35),
				EmissionDirection = Enum.NormalId.Top,
				LightEmission = 1,
				LightInfluence = 0,
				Size = bubble(.35, .15),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(.15, .1),
					NumberSequenceKeypoint.new(.8, .3),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Color = ColorSequence.new(Color3.fromRGB(255,70,40), Color3.fromRGB(255,170,70)),
			}, embers)

			modeSound(RED_MOON_SOUND_ID, .3)

			local dir = Vector3.new(.35,.38,-.86).Unit

			return function(dt, t)
				local cp = camPos()
				anchor.Position = cp + dir * 520

				for i,h in ipairs(halos) do
					h.f.BackgroundTransparency = h.base + .035 * math.sin(t * 1.1 + i)
				end

				for _,c in ipairs(clouds) do
					c.f.Position = UDim2.fromScale(.5 + .12 * math.sin(t * .15 + c.phase), c.y)
				end

				local root = getRoot()
				if root then
					embers.Position = root.Position + Vector3.new(0,-2,0)
				end
			end
		end

		-- GOLDEN PEACE (sunrise glow, sun rays, falling light, halo) -----------------

		Modes.peace = function()

			stashSkyAtmos()

			setLight{
				ClockTime = 10.5,
				Brightness = 2.6,
				Ambient = Color3.fromRGB(200,180,130),
				OutdoorAmbient = Color3.fromRGB(235,210,160),
				FogStart = 40,
				FogEnd = 900,
				FogColor = Color3.fromRGB(255,235,190),
				ExposureCompensation = .05,
			}

			mk("Sky", { Name = "AAYAN_PEACE_SKY", StarCount = 0, CelestialBodiesShown = true }, Lighting)

			mk("Atmosphere", {
				Name = "AAYAN_PEACE_ATMOSPHERE",
				Density = .2, Offset = .2, Haze = .5, Glare = .35,
				Color = Color3.fromRGB(255,232,175),
				Decay = Color3.fromRGB(255,200,110),
			}, Lighting)

			mk("BloomEffect", { Name = "AAYAN_PEACE_BLOOM", Intensity = .32, Size = 30, Threshold = .95 }, Lighting)
			mk("SunRaysEffect", { Name = "AAYAN_PEACE_RAYS", Intensity = .22, Spread = .85 }, Lighting)
			mk("ColorCorrectionEffect", {
				Name = "AAYAN_GOLDEN_SCREEN",
				TintColor = Color3.fromRGB(255,243,210),
				Brightness = .04, Contrast = .03, Saturation = .1,
			}, Lighting)

			-- gold sparkles falling slowly over the player
			local field = emitterPart("AAYAN_PEACE_FIELD", Vector3.new(90,1,90))

			mk("ParticleEmitter", {
				Texture = SPARK,
				Rate = 34,
				Lifetime = NumberRange.new(9,14),
				Speed = NumberRange.new(.5,1.5),
				Acceleration = Vector3.new(.6,-1.3,.4),
				SpreadAngle = Vector2.new(180,180),
				RotSpeed = NumberRange.new(-40,40),
				LightEmission = 1,
				LightInfluence = 0,
				Size = bubble(.35, .15),
				Transparency = fade(.1),
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255,220,80)),
					ColorSequenceKeypoint.new(.5, Color3.fromRGB(255,245,175)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255,190,50)),
				}),
			}, field)

			-- big soft light orbs
			mk("ParticleEmitter", {
				Texture = SMOKE,
				Rate = 3,
				Lifetime = NumberRange.new(10,14),
				Speed = NumberRange.new(.3,1),
				Acceleration = Vector3.new(0,.4,0),
				SpreadAngle = Vector2.new(180,180),
				LightEmission = 1,
				LightInfluence = 0,
				Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 2),
					NumberSequenceKeypoint.new(1, 6),
				}),
				Transparency = fade(.86),
				Color = ColorSequence.new(Color3.fromRGB(255,228,150), Color3.fromRGB(255,205,110)),
			}, field)

			-- soft golden glow around the character + halo above the head
			local glow = highlightChar(Color3.fromRGB(255,214,90), .88, Color3.fromRGB(255,228,130), .55)

			local char = player.Character
			local head = char and char:FindFirstChild("Head")
			if head then
				local bb = track(mk("BillboardGui", {
					Name = "AAYAN_HALO",
					Size = UDim2.fromOffset(78,30),
					StudsOffset = Vector3.new(0,2,0),
					AlwaysOnTop = true,
					LightInfluence = 0,
					Adornee = head,
				}, head))

				local outer = mk("Frame", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(.5,.5),
					Position = UDim2.fromScale(.5,.5),
					Size = UDim2.fromScale(.92,.5),
				}, bb)
				mk("UICorner", { CornerRadius = UDim.new(1,0) }, outer)
				mk("UIStroke", { Color = Color3.fromRGB(255,215,80), Thickness = 4, Transparency = .05 }, outer)

				local aura = mk("Frame", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(.5,.5),
					Position = UDim2.fromScale(.5,.5),
					Size = UDim2.fromScale(1,.64),
				}, bb)
				mk("UICorner", { CornerRadius = UDim.new(1,0) }, aura)
				mk("UIStroke", { Color = Color3.fromRGB(255,240,170), Thickness = 8, Transparency = .78 }, aura)
			end

			modeSound(PEACE_SOUND_ID, .22)

			return function(dt, t)
				local root = getRoot()
				if root then
					field.Position = root.Position + Vector3.new(0,24,0)
				end
				if glow then
					glow.FillTransparency = .86 + .04 * math.sin(t * 1.4)
				end
			end
		end

		-- RAINBOW (huge rainbow arc + colour-cycling sky) ----------------------------

		local RAINBOW = {
			Color3.fromRGB(255,40,40), Color3.fromRGB(255,140,30), Color3.fromRGB(255,235,40),
			Color3.fromRGB(60,220,80), Color3.fromRGB(50,170,255), Color3.fromRGB(80,80,255),
			Color3.fromRGB(180,80,255),
		}

		Modes.rainbow = function()

			stashSkyAtmos()

			setLight{
				ClockTime = 14,
				Brightness = 2.6,
				Ambient = Color3.fromRGB(175,175,200),
				OutdoorAmbient = Color3.fromRGB(190,190,215),
				FogStart = 200,
				FogEnd = 5000,
				ExposureCompensation = .1,
			}

			mk("Sky", { Name = "AAYAN_RAINBOW_SKY", StarCount = 0, CelestialBodiesShown = true }, Lighting)

			local atmos = mk("Atmosphere", {
				Name = "AAYAN_RAINBOW_ATMOSPHERE",
				Density = .25, Offset = .25, Haze = .8, Glare = .3,
				Color = Color3.fromRGB(255,200,230),
				Decay = Color3.fromRGB(200,160,255),
			}, Lighting)

			local tint = mk("ColorCorrectionEffect", {
				Name = "AAYAN_RAINBOW_TINT",
				TintColor = Color3.fromRGB(255,235,245),
				Saturation = .25, Contrast = .05, Brightness = .02,
			}, Lighting)

			mk("BloomEffect", { Name = "AAYAN_RAINBOW_BLOOM", Intensity = .3, Size = 26, Threshold = .95 }, Lighting)

			local arc = emitterPart("AAYAN_RAINBOW_ARC", Vector3.new(820,430,1))
			local sg = mk("SurfaceGui", {
				Face = Enum.NormalId.Front,
				SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
				PixelsPerStud = 1,
				LightInfluence = 0,
				Brightness = 1.4,
				AlwaysOnTop = false,
			}, arc)
			local box = mk("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1,1),
				ClipsDescendants = true,
			}, sg)

			for i,col in ipairs(RAINBOW) do
				local d = 640 - (i - 1) * 36
				local ring = mk("Frame", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(.5,.5),
					Position = UDim2.fromOffset(410,410),
					Size = UDim2.fromOffset(d,d),
				}, box)
				mk("UICorner", { CornerRadius = UDim.new(1,0) }, ring)
				mk("UIStroke", { Color = col, Thickness = 18, Transparency = .15 }, ring)
			end

			-- colourful sparkles around the player
			local field = emitterPart("AAYAN_RAINBOW_FIELD", Vector3.new(80,1,80))
			mk("ParticleEmitter", {
				Texture = SPARK,
				Rate = 30,
				Lifetime = NumberRange.new(6,10),
				Speed = NumberRange.new(.5,2),
				Acceleration = Vector3.new(0,-.8,0),
				SpreadAngle = Vector2.new(180,180),
				LightEmission = 1,
				LightInfluence = 0,
				Size = bubble(.4, .15),
				Transparency = fade(.1),
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255,80,120)),
					ColorSequenceKeypoint.new(.25, Color3.fromRGB(255,220,60)),
					ColorSequenceKeypoint.new(.5, Color3.fromRGB(80,255,140)),
					ColorSequenceKeypoint.new(.75, Color3.fromRGB(70,170,255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(200,90,255)),
				}),
			}, field)

			local glow = highlightChar(Color3.fromRGB(255,255,255), .85, Color3.fromRGB(255,255,255), .4)

			local dir = Vector3.new(.55,0,-.83)

			return function(dt, t)
				local cp = camPos()
				local pos = cp + Vector3.new(dir.X * 650, 170, dir.Z * 650)
				arc.CFrame = CFrame.lookAt(pos, Vector3.new(cp.X, pos.Y, cp.Z))

				local h = (t * .05) % 1
				atmos.Color = Color3.fromHSV(h, .45, 1)
				atmos.Decay = Color3.fromHSV((h + .12) % 1, .5, 1)
				tint.TintColor = Color3.fromHSV((h + .5) % 1, .22, 1)

				if glow then
					local g = Color3.fromHSV((t * .25) % 1, .9, 1)
					glow.FillColor = g
					glow.OutlineColor = g
				end

				local root = getRoot()
				if root then
					field.Position = root.Position + Vector3.new(0,20,0)
				end
			end
		end

		-- AURORA (flowing curtains of light, stars) ----------------------------------

		local AURORA_PALETTES = {
			{ Color3.fromRGB(170,90,255), Color3.fromRGB(60,220,255), Color3.fromRGB(60,255,140) },
			{ Color3.fromRGB(255,90,200), Color3.fromRGB(80,140,255), Color3.fromRGB(60,255,220) },
			{ Color3.fromRGB(100,255,160), Color3.fromRGB(60,230,200), Color3.fromRGB(120,120,255) },
		}

		Modes.aurora = function()

			stashSkyAtmos()

			setLight{
				ClockTime = 0,
				Brightness = .5,
				Ambient = Color3.fromRGB(18,30,50),
				OutdoorAmbient = Color3.fromRGB(25,45,70),
				FogStart = 100,
				FogEnd = 4000,
				FogColor = Color3.fromRGB(10,20,35),
			}

			mk("Sky", { Name = "AAYAN_AURORA_SKY", StarCount = 4000, CelestialBodiesShown = false }, Lighting)

			mk("Atmosphere", {
				Name = "AAYAN_AURORA_ATMOSPHERE",
				Density = .12, Offset = 0, Haze = .6, Glare = 0,
				Color = Color3.fromRGB(40,80,120),
				Decay = Color3.fromRGB(10,25,50),
			}, Lighting)

			mk("ColorCorrectionEffect", {
				Name = "AAYAN_AURORA_TINT",
				TintColor = Color3.fromRGB(200,240,255),
				Saturation = .15, Contrast = .08,
			}, Lighting)

			mk("BloomEffect", { Name = "AAYAN_AURORA_BLOOM", Intensity = .45, Size = 30, Threshold = .85 }, Lighting)

			local segments = {}
			local RIBBONS, SEGS = 3, 9

			for k = 1, RIBBONS do
				local pal = AURORA_PALETTES[k]
				for i = 1, SEGS do
					local part = emitterPart("AAYAN_AURORA_SEG", Vector3.new(96,150,.2))
					local sg = mk("SurfaceGui", {
						Face = Enum.NormalId.Front,
						SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
						PixelsPerStud = 1,
						LightInfluence = 0,
						Brightness = 3,
						AlwaysOnTop = false,
					}, part)
					local f = mk("Frame", {
						BackgroundColor3 = Color3.new(1,1,1),
						BorderSizePixel = 0,
						Size = UDim2.fromScale(1,1),
					}, sg)
					local g = mk("UIGradient", {
						Rotation = 90,
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, pal[1]),
							ColorSequenceKeypoint.new(.5, pal[2]),
							ColorSequenceKeypoint.new(1, pal[3]),
						}),
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 1),
							NumberSequenceKeypoint.new(.3, .72),
							NumberSequenceKeypoint.new(.85, .35),
							NumberSequenceKeypoint.new(1, .9),
						}),
					}, f)
					segments[#segments + 1] = { part = part, grad = g, k = k, i = i }
				end
			end

			return function(dt, t)
				local cp = camPos()
				local span = 1.6

				for _,s in ipairs(segments) do
					local radius = 450 + 40 * s.k
					local theta = (s.k - 1) * (math.pi * 2 / RIBBONS) + .5
						+ (s.i - 1) * (span / (SEGS - 1))
						+ .15 * math.sin(t * .3 + s.i * .5 + s.k)
					local y = cp.Y + 170 + s.k * 25 + 40 * math.sin(t * .4 + s.i * .7 + s.k)

					local pos = Vector3.new(cp.X + math.cos(theta) * radius, y, cp.Z + math.sin(theta) * radius)
					s.part.CFrame = CFrame.lookAt(pos, Vector3.new(cp.X, y, cp.Z))
						* CFrame.Angles(0, 0, .06 * math.sin(t * .5 + s.i))

					s.grad.Offset = Vector2.new(0, .06 * math.sin(t * .8 + s.i * .6 + s.k))
				end
			end
		end

		-- GALAXY (stars everywhere, nebula clouds, spiral galaxies, shooting stars) ---

		Modes.galaxy = function()

			stashSkyAtmos()

			setLight{
				ClockTime = 0,
				Brightness = .5,
				Ambient = Color3.fromRGB(40,22,70),
				OutdoorAmbient = Color3.fromRGB(55,32,95),
				FogStart = 500,
				FogEnd = 100000,
				FogColor = Color3.fromRGB(10,5,25),
			}

			mk("Sky", { Name = "AAYAN_GALAXY_SKY", StarCount = 5000, CelestialBodiesShown = false }, Lighting)

			mk("Atmosphere", {
				Name = "AAYAN_GALAXY_ATMOSPHERE",
				Density = .06, Offset = 0, Haze = .3, Glare = 0,
				Color = Color3.fromRGB(70,40,140),
				Decay = Color3.fromRGB(20,8,50),
			}, Lighting)

			mk("ColorCorrectionEffect", {
				Name = "AAYAN_GALAXY_TINT",
				TintColor = Color3.fromRGB(225,215,255),
				Saturation = .25, Contrast = .1,
			}, Lighting)

			mk("BloomEffect", { Name = "AAYAN_GALAXY_BLOOM", Intensity = .5, Size = 32, Threshold = .85 }, Lighting)

			-- a sphere of sky particles that is locked to the camera, like a sky box
			local dome = emitterPart("AAYAN_GALAXY_DOME", Vector3.new(900,900,900))

			local function skyEmitter(props, count)
				local base = {
					Speed = NumberRange.new(0,0),
					LightEmission = 1,
					LightInfluence = 0,
					LockedToPart = true,
					Shape = Enum.ParticleEmitterShape.Sphere,
					ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
				}
				for k,v in pairs(props) do base[k] = v end
				local e = mk("ParticleEmitter", base, dome)
				e:Emit(count)
				return e
			end

			-- nebula clouds (purple / blue / pink)
			for _,n in ipairs({
				{ Color3.fromRGB(150,60,255), Color3.fromRGB(90,40,220), 44 },
				{ Color3.fromRGB(60,140,255), Color3.fromRGB(40,210,255), 36 },
				{ Color3.fromRGB(255,70,190), Color3.fromRGB(190,50,255), 30 },
			}) do
				skyEmitter({
					Texture = SMOKE,
					Rate = n[3] / 90,
					Lifetime = NumberRange.new(80,100),
					Rotation = NumberRange.new(0,360),
					RotSpeed = NumberRange.new(-2,2),
					Size = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 130, 50),
						NumberSequenceKeypoint.new(1, 130, 50),
					}),
					Transparency = fade(.84),
					Color = ColorSequence.new(n[1], n[2]),
				}, n[3])
			end

			-- twinkling stars (white / gold / ice blue)
			for _,s in ipairs({
				{ Color3.fromRGB(255,255,255), Color3.fromRGB(230,240,255), 600, 70 },
				{ Color3.fromRGB(255,230,160), Color3.fromRGB(255,190,120), 220, 30 },
				{ Color3.fromRGB(150,200,255), Color3.fromRGB(190,150,255), 260, 34 },
			}) do
				skyEmitter({
					Texture = SPARK,
					Rate = s[4],
					Lifetime = NumberRange.new(7,13),
					Rotation = NumberRange.new(0,360),
					Size = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(.5, 7, 3),
						NumberSequenceKeypoint.new(1, 0),
					}),
					Transparency = NumberSequence.new(0),
					Color = ColorSequence.new(s[1], s[2]),
				}, s[3])
			end

			-- two spiral galaxies drawn in the sky
			local galaxies = {}
			local function galaxy(dir, studs, colors)
				local anchor = emitterPart("AAYAN_GALAXY_CORE", Vector3.new(1,1,1))
				local bb = mk("BillboardGui", {
					Size = UDim2.new(studs,0,studs,0),
					AlwaysOnTop = false,
					LightInfluence = 0,
					ResetOnSpawn = false,
					Adornee = anchor,
				}, anchor)

				local layers = {}
				for i,l in ipairs({
					{1.00,.46,.93}, {.85,.36,.88}, {.68,.27,.84}, {.50,.19,.78}, {.30,.11,.62},
				}) do
					local f = circle(bb, l[1], l[2], colors[math.min(i, #colors)], l[3])
					f.Rotation = -28
					layers[#layers + 1] = { f = f, speed = .4 + i * .15, base = -28 }
				end
				for i,a in ipairs({ 0, 60, 120 }) do
					local arm = circle(bb, .9, .07, colors[1]:Lerp(Color3.new(1,1,1), .35), .8)
					arm.Rotation = a - 28
					layers[#layers + 1] = { f = arm, speed = .7 + i * .1, base = a - 28 }
				end
				circle(bb, .12, .12, Color3.new(1,1,1), .15)
				galaxies[#galaxies + 1] = { anchor = anchor, dir = dir.Unit, dist = 700, layers = layers }
			end

			galaxy(Vector3.new(-.55,.50,-.67), 520, {
				Color3.fromRGB(110,60,255), Color3.fromRGB(150,80,255), Color3.fromRGB(255,120,220),
				Color3.fromRGB(255,190,240), Color3.fromRGB(255,245,230),
			})
			galaxy(Vector3.new(.70,.30,.65), 240, {
				Color3.fromRGB(60,140,255), Color3.fromRGB(70,200,255), Color3.fromRGB(150,230,255),
				Color3.fromRGB(220,245,255), Color3.fromRGB(255,255,255),
			})

			-- shooting stars
			local meteors = {}
			local nextMeteor = os.clock() + 2

			local function spawnMeteor()
				local az = math.random() * math.pi * 2
				local el = math.rad(math.random(30, 70))
				local dirA = Vector3.new(math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el))
				local tangent = Vector3.new(-math.sin(az), 0, math.cos(az))
				local p = mk("Part", {
					Name = "AAYAN_METEOR",
					Anchored = true,
					CanCollide = false,
					CanTouch = false,
					CanQuery = false,
					Material = Enum.Material.Neon,
					Color = Color3.fromRGB(255,240,210),
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(3,3,3),
				}, envFolder)
				local a0 = mk("Attachment", { Position = Vector3.new(0,2.5,0) }, p)
				local a1 = mk("Attachment", { Position = Vector3.new(0,-2.5,0) }, p)
				mk("Trail", {
					Attachment0 = a0,
					Attachment1 = a1,
					Lifetime = .9,
					LightEmission = 1,
					Color = ColorSequence.new(Color3.fromRGB(255,255,255), Color3.fromRGB(120,160,255)),
					Transparency = NumberSequence.new(0, 1),
					WidthScale = NumberSequence.new(1, 0),
				}, p)
				meteors[#meteors + 1] = {
					p = p,
					s = dirA * 420 - tangent * 170,
					e = dirA * 420 + tangent * 170 + Vector3.new(0,-90,0),
					t0 = os.clock(),
					dur = 1.1,
				}
			end

			return function(dt, t)
				local cp = camPos()
				dome.Position = cp

				for _,g in ipairs(galaxies) do
					g.anchor.Position = cp + g.dir * g.dist
					for _,l in ipairs(g.layers) do
						l.f.Rotation = l.base + t * l.speed
					end
				end

				if t >= nextMeteor then
					nextMeteor = t + 3 + math.random() * 4
					spawnMeteor()
				end

				for i = #meteors, 1, -1 do
					local m = meteors[i]
					local a = (t - m.t0) / m.dur
					if a >= 1 then
						m.p:Destroy()
						table.remove(meteors, i)
					else
						m.p.Position = cp + m.s:Lerp(m.e, a)
					end
				end
			end
		end

		-- SUNSET -----------------------------------------------------------------------

		Modes.sunset = function()

			stashSkyAtmos()

			setLight{
				ClockTime = 17.7,
				Brightness = 2.2,
				Ambient = Color3.fromRGB(170,110,90),
				OutdoorAmbient = Color3.fromRGB(205,135,100),
				FogStart = 80,
				FogEnd = 1500,
				FogColor = Color3.fromRGB(255,150,90),
			}

			mk("Sky", { Name = "AAYAN_SUNSET_SKY", StarCount = 0, CelestialBodiesShown = true }, Lighting)

			mk("Atmosphere", {
				Name = "AAYAN_SUNSET_ATMOSPHERE",
				Density = .33, Offset = .3, Haze = 1.2, Glare = .8,
				Color = Color3.fromRGB(255,165,105),
				Decay = Color3.fromRGB(255,90,60),
			}, Lighting)

			mk("SunRaysEffect", { Name = "AAYAN_SUNSET_RAYS", Intensity = .3, Spread = 1 }, Lighting)
			mk("BloomEffect", { Name = "AAYAN_SUNSET_BLOOM", Intensity = .35, Size = 28, Threshold = .9 }, Lighting)
			mk("ColorCorrectionEffect", {
				Name = "AAYAN_SUNSET_TINT",
				TintColor = Color3.fromRGB(255,225,200),
				Saturation = .2, Contrast = .06,
			}, Lighting)
		end

		-- SNOWFALL ---------------------------------------------------------------------

		Modes.snow = function()

			stashSkyAtmos()

			setLight{
				ClockTime = 15,
				Brightness = 1.3,
				Ambient = Color3.fromRGB(150,160,180),
				OutdoorAmbient = Color3.fromRGB(170,180,200),
				FogStart = 20,
				FogEnd = 420,
				FogColor = Color3.fromRGB(205,215,230),
			}

			mk("Sky", { Name = "AAYAN_SNOW_SKY", StarCount = 0, CelestialBodiesShown = false }, Lighting)

			mk("Atmosphere", {
				Name = "AAYAN_SNOW_ATMOSPHERE",
				Density = .38, Offset = 0, Haze = 1.6, Glare = 0,
				Color = Color3.fromRGB(200,212,230),
				Decay = Color3.fromRGB(160,175,205),
			}, Lighting)

			mk("ColorCorrectionEffect", {
				Name = "AAYAN_SNOW_TINT",
				TintColor = Color3.fromRGB(225,238,255),
				Saturation = -.1, Contrast = .05,
			}, Lighting)

			local field = emitterPart("AAYAN_SNOW_FIELD", Vector3.new(110,1,110))
			mk("ParticleEmitter", {
				Texture = SMOKE,
				Rate = 240,
				Lifetime = NumberRange.new(6,8),
				Speed = NumberRange.new(0,1),
				Acceleration = Vector3.new(3,-9,1.5),
				SpreadAngle = Vector2.new(15,15),
				EmissionDirection = Enum.NormalId.Bottom,
				LightEmission = .3,
				LightInfluence = 0,
				Size = NumberSequence.new(.3, .15),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(.1, .15),
					NumberSequenceKeypoint.new(.9, .15),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Color = ColorSequence.new(Color3.new(1,1,1)),
			}, field)

			return function(dt, t)
				local cp = camPos()
				field.Position = cp + Vector3.new(0,45,0)
			end
		end

		-- NEON NIGHT -------------------------------------------------------------------

		Modes.neon = function()

			stashSkyAtmos()

			setLight{
				ClockTime = 0,
				Brightness = .6,
				Ambient = Color3.fromRGB(30,5,60),
				OutdoorAmbient = Color3.fromRGB(40,10,80),
				FogStart = 40,
				FogEnd = 700,
				FogColor = Color3.fromRGB(30,5,60),
			}

			mk("Sky", { Name = "AAYAN_NEON_SKY", StarCount = 2500, CelestialBodiesShown = false }, Lighting)

			local atmos = mk("Atmosphere", {
				Name = "AAYAN_NEON_ATMOSPHERE",
				Density = .3, Offset = 0, Haze = 1.5, Glare = 0,
				Color = Color3.fromRGB(150,40,220),
				Decay = Color3.fromRGB(60,10,110),
			}, Lighting)

			local tint = mk("ColorCorrectionEffect", {
				Name = "AAYAN_NEON_TINT",
				TintColor = Color3.fromRGB(255,120,230),
				Saturation = .35, Contrast = .15,
			}, Lighting)

			mk("BloomEffect", { Name = "AAYAN_NEON_BLOOM", Intensity = 1.1, Size = 34, Threshold = .8 }, Lighting)

			local glow = highlightChar(Color3.fromRGB(0,230,255), .8, Color3.fromRGB(255,60,220), .2)

			local magenta, cyan = Color3.fromRGB(255,60,210), Color3.fromRGB(40,225,255)

			return function(dt, t)
				local k = (math.sin(t * .8) + 1) / 2
				local c = magenta:Lerp(cyan, k)
				tint.TintColor = c:Lerp(Color3.new(1,1,1), .35)
				atmos.Color = c:Lerp(Color3.fromRGB(80,20,140), .4)
				if glow then
					glow.FillColor = cyan:Lerp(magenta, k)
					glow.OutlineColor = magenta:Lerp(cyan, k)
				end
			end
		end



		-- CLEAR DAY ------------------------------------------------------------------------------------------
		Modes.clear = function()
			stashSkyAtmos()
			setLight{
				ClockTime = 14, Brightness = 3, Ambient = Color3.fromRGB(150, 160, 180),
				OutdoorAmbient = Color3.fromRGB(165, 175, 195), FogStart = 600, FogEnd = 100000,
				FogColor = Color3.fromRGB(190, 210, 235), ExposureCompensation = 0,
			}
			mk("Sky", { Name = "AAYAN_CLEAR_SKY", StarCount = 0, CelestialBodiesShown = true }, Lighting)
			mk("Atmosphere", {
				Name = "AAYAN_CLEAR_ATMOS", Density = 0.28, Offset = 0.25, Glare = 0.2, Haze = 0.4,
				Color = Color3.fromRGB(190, 210, 240), Decay = Color3.fromRGB(106, 112, 125),
			}, Lighting)
			mk("SunRaysEffect", { Name = "AAYAN_CLEAR_RAYS", Intensity = 0.08, Spread = 0.6 }, Lighting)
			mk("ColorCorrectionEffect", { Name = "AAYAN_CLEAR_CC", Saturation = 0.12, Contrast = 0.05 }, Lighting)
		end

		-- RAIN + THUNDERSTORM ---------------------------------------------------------------------------
		local function rain(stormy)
			stashSkyAtmos()
			setLight{
				ClockTime = stormy and 22.2 or 16.5, Brightness = stormy and 0.5 or 1,
				Ambient = Color3.fromRGB(70, 78, 95), OutdoorAmbient = Color3.fromRGB(80, 88, 105),
				FogStart = 10, FogEnd = stormy and 220 or 320, FogColor = Color3.fromRGB(80, 88, 100),
			}
			mk("Sky", { Name = "AAYAN_RAIN_SKY", StarCount = 0, CelestialBodiesShown = false }, Lighting)
			mk("Atmosphere", {
				Name = "AAYAN_RAIN_ATMOS", Density = stormy and 0.5 or 0.4, Offset = 0, Haze = 2, Glare = 0,
				Color = Color3.fromRGB(90, 98, 112), Decay = Color3.fromRGB(40, 44, 55),
			}, Lighting)
			mk("ColorCorrectionEffect", {
				Name = "AAYAN_RAIN_CC", TintColor = Color3.fromRGB(190, 205, 230), Saturation = -0.2, Contrast = 0.1,
				Brightness = stormy and -0.08 or -0.03,
			}, Lighting)

			local field = emitterPart("AAYAN_RAIN_FIELD", Vector3.new(120, 1, 120))
			mk("ParticleEmitter", {
				Texture = SMOKE, Rate = stormy and 700 or 450, Lifetime = NumberRange.new(0.6, 0.8),
				Speed = NumberRange.new(80, 100), Acceleration = Vector3.new(-8, -40, 0),
				EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(4, 4),
				Orientation = Enum.ParticleOrientation.VelocityParallel,
				LightEmission = 0.3, LightInfluence = 0, Size = NumberSequence.new(0.22),
				Transparency = NumberSequence.new(0.55), Color = ColorSequence.new(Color3.fromRGB(190, 215, 255)),
			}, field)
			-- splash mist near the ground around the player
			local mist = emitterPart("AAYAN_RAIN_MIST", Vector3.new(70, 1, 70))
			mk("ParticleEmitter", {
				Texture = SMOKE, Rate = 14, Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(1, 3),
				SpreadAngle = Vector2.new(180, 180), EmissionDirection = Enum.NormalId.Top,
				LightInfluence = 1, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 9) }),
				Transparency = fade(0.9), Color = ColorSequence.new(Color3.fromRGB(160, 170, 185)),
			}, mist)

			local snd
			if stormy then
				snd = track(mk("Sound", { Name = "AAYAN_THUNDER", SoundId = THUNDER_ID, Volume = 0.6 }, sg))
			end
			local nextBolt = os.clock() + 3

			return function(dt, t)
				local cp = camPos()
				field.Position = cp + Vector3.new(0, 40, 0)
				mist.Position = cp + Vector3.new(0, -3, 0)

				if stormy and t >= nextBolt then
					nextBolt = t + 4 + math.random() * 6
					local flash = mk("ColorCorrectionEffect", {
						Name = "AAYAN_STORM_FLASH", Brightness = 1.3, Contrast = 0.2, TintColor = Color3.fromRGB(225, 235, 255),
					}, Lighting)
					task.delay(0.1, function() if flash.Parent then flash:Destroy() end end)
					local root = getRootW()
					if root then
						local a = math.random() * math.pi * 2
						local bp = root.Position + Vector3.new(math.cos(a) * 70, 40, math.sin(a) * 70)
						local bolt = mk("Part", {
							Name = "AAYAN_BOLT", Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
							Material = Enum.Material.Neon, Color = Color3.fromRGB(230, 240, 255), Size = Vector3.new(0.6, 90, 0.6),
							CFrame = CFrame.new(bp),
						}, envFolder)
						task.delay(0.14, function() if bolt.Parent then bolt:Destroy() end end)
					end
					if snd then
						task.delay(0.4, function()
							if snd.Parent then snd.TimePosition = 0 snd:Play() end
						end)
					end
				end
			end
		end

		Modes.rain = function() return rain(false) end
		Modes.storm = function() return rain(true) end

		-- HEAVY FOG ----------------------------------------------------------------------------------------------
		Modes.fog = function()
			stashSkyAtmos()
			setLight{
				ClockTime = 12, Brightness = 1.6, Ambient = Color3.fromRGB(150, 155, 165),
				OutdoorAmbient = Color3.fromRGB(165, 170, 180), FogStart = 4, FogEnd = 95, FogColor = Color3.fromRGB(190, 195, 205),
			}
			mk("Sky", { Name = "AAYAN_FOG_SKY", StarCount = 0, CelestialBodiesShown = false }, Lighting)
			mk("Atmosphere", {
				Name = "AAYAN_FOG_ATMOS", Density = 0.72, Offset = 0, Haze = 3, Glare = 0,
				Color = Color3.fromRGB(195, 200, 210), Decay = Color3.fromRGB(160, 165, 178),
			}, Lighting)
			mk("ColorCorrectionEffect", { Name = "AAYAN_FOG_CC", Saturation = -0.25, Contrast = -0.05, TintColor = Color3.fromRGB(230, 235, 245) }, Lighting)

			local drift = emitterPart("AAYAN_FOG_DRIFT", Vector3.new(100, 1, 100))
			mk("ParticleEmitter", {
				Texture = SMOKE, Rate = 10, Lifetime = NumberRange.new(8, 12), Speed = NumberRange.new(1, 3),
				SpreadAngle = Vector2.new(180, 180), EmissionDirection = Enum.NormalId.Top,
				LightInfluence = 1, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(1, 24) }),
				Transparency = fade(0.86), Color = ColorSequence.new(Color3.fromRGB(205, 210, 220)),
			}, drift)
			return function()
				drift.Position = camPos() + Vector3.new(0, -2, 0)
			end
		end

		-- ENGINE ------------------------------------------------------------------------------------------------------
		W.names = {
			{ "dark", "Dark Weather" }, { "moon", "Red Moon" }, { "peace", "Golden Peace" },
			{ "rainbow", "Rainbow" }, { "aurora", "Aurora" }, { "galaxy", "Galaxy (full sky)" },
			{ "sunset", "Sunset" }, { "snow", "Snowfall" }, { "neon", "Neon Night" },
			{ "clear", "Clear Day" }, { "rain", "Rain" }, { "storm", "Thunderstorm" }, { "fog", "Heavy Fog" },
		}

		function W.stop()
			modeUpdate = nil
			desired, mine = nil, {}
			for _, i in ipairs(tracked) do pcall(function() i:Destroy() end) end
			tracked = {}
			if envFolder then envFolder:ClearAllChildren() end
			for _, v in ipairs(Lighting:GetChildren()) do
				if v.Name:sub(1, 6) == "AAYAN_" then v:Destroy() end
			end
			for _, v in ipairs(stashed) do pcall(function() v.Parent = Lighting end) end
			stashed = {}
			if Original and W.active then
				setLight(Original)
			end
			W.active = nil
		end

		function W.start(key)
			local first = (W.active == nil)
			if first then
				Original = {
					ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
					OutdoorAmbient = Lighting.OutdoorAmbient, FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd,
					FogColor = Lighting.FogColor, ExposureCompensation = Lighting.ExposureCompensation,
				}
			end
			local keepOriginal = Original
			W.stop()
			Original = keepOriginal

			if not envFolder or not envFolder.Parent then
				envFolder = Instance.new("Folder")
				envFolder.Name = "AAYAN_ADMIN_ENV"
				envFolder.Parent = workspace
			end

			W.active = key
			local ok, result = pcall(Modes[key])
			if ok then
				modeUpdate = result
				desired = {}
				for k in pairs(Original) do desired[k] = Lighting[k] end
				for _, v in ipairs(Lighting:GetChildren()) do
					if v.Name:sub(1, 6) == "AAYAN_" then mine[#mine + 1] = v end
				end
			else
				warn("[AAYAN] weather failed: " .. tostring(result))
				W.stop()
				notify("Weather failed", tostring(result), "warn")
			end
		end

		function W.toggle(key)
			if W.active == key then W.stop() else W.start(key) end
		end

		function F.weatherStop()
			if W.active then W.stop() end
			if envFolder then envFolder:Destroy() envFolder = nil end
		end

		-- keeper: games reset lighting every second, so we put our values back
		function F.weatherKeep()
			if not W.active or not desired then return end
			for k, v in pairs(desired) do
				if Lighting[k] ~= v then Lighting[k] = v end
			end
			for _, v in ipairs(mine) do
				if v.Parent ~= Lighting then pcall(function() v.Parent = Lighting end) end
			end
			for _, v in ipairs(Lighting:GetChildren()) do
				if (v:IsA("Sky") or v:IsA("Atmosphere")) and v.Name:sub(1, 6) ~= "AAYAN_" then
					if #stashed < 40 then
						stashed[#stashed + 1] = v
						v.Parent = nil
					end
				end
			end
		end

		function F.weatherUpdate(dt, t)
			local f = modeUpdate
			if f then
				local ok, err = pcall(f, dt, t)
				if not ok then
					warn("[AAYAN] weather update error: " .. tostring(err))
					modeUpdate = nil
				end
			end
		end

		function F.weatherReapply()
			local k = W.active
			if k then
				task.delay(0.2, function() if alive then W.start(k) end end)
			end
		end
	end

	--==============================================
	-- WINDOW (landscape hub like the concept art)
	--==============================================

	S.pad = true
	S.zoom = 12

	local WW, WH = 610, 372
	local HEAD, SIDE = 52, 142

	local holder = new("Frame", {
		Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 40, 0.5, 0),
		Size = UDim2.fromOffset(WW, WH), BackgroundTransparency = 1, Visible = false,
	}, sg)
	local holderScale = new("UIScale", {}, holder)

	local win = new("CanvasGroup", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = NAVY, BackgroundTransparency = S.bgTrans,
		BorderSizePixel = 0, GroupTransparency = 1,
	}, holder)
	corner(win, 18)
	local winStroke = stroke(win, Color3.new(1, 1, 1), 2.6, 0)
	local winGrad = accentGrad(winStroke, 0)

	local function fitScale()
		local c = workspace.CurrentCamera
		if not c then return end
		local v = c.ViewportSize
		holderScale.Scale = math.clamp(math.min(v.X / (WW + 30), v.Y / (WH + 30)), 0.45, 1.3) * S.scale
	end

	-- header --------------------------------------------------------------------------------
	local header = new("Frame", {
		Size = UDim2.new(1, 0, 0, HEAD), BackgroundColor3 = Color3.fromRGB(12, 14, 36),
		BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 20,
	}, win)
	new("Frame", {
		Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = CYAN, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 21,
	}, header)

	-- drawn crown logo
	local function crown(parent, x, y, sc, z)
		local c = new("Frame", {
			Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(34 * sc, 28 * sc), BackgroundTransparency = 1, ZIndex = z,
		}, parent)
		local base = new("Frame", {
			Position = UDim2.fromOffset(2 * sc, 20 * sc), Size = UDim2.fromOffset(30 * sc, 7 * sc),
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = z,
		}, c)
		corner(base, 3)
		accentGrad(base, 0)
		for i, d in ipairs({ { 2, 4 }, { 13, 0 }, { 24, 4 } }) do
			local p = new("Frame", {
				Position = UDim2.fromOffset(d[1] * sc, d[2] * sc), Size = UDim2.fromOffset(9 * sc, 17 * sc),
				BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = z,
				Rotation = (i == 1 and -14) or (i == 3 and 14) or 0,
			}, c)
			corner(p, 3)
			accentGrad(p, 90)
			local dot = new("Frame", {
				Position = UDim2.fromOffset(d[1] * sc + 1.5 * sc, (d[2] - 3) * sc), Size = UDim2.fromOffset(6 * sc, 6 * sc),
				BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = z,
			}, c)
			corner(dot, 6)
		end
		return c
	end
	crown(header, 14, 12, 1.1, 22)

	local title = lbl(header, "AAYAN ADMIN V3", 21, Color3.new(1, 1, 1), Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(58, 4), Size = UDim2.fromOffset(220, 26), ZIndex = 22,
	})
	local titleGrad = accentGrad(title, 0)
	lbl(header, "ULTIMATE CONTROL HUB • 143 FEATURES", 9, Color3.fromRGB(190, 210, 255), Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(60, 29), Size = UDim2.fromOffset(230, 14), ZIndex = 22,
	})

	local function hdrButton(text, order, color)
		local b = new("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10 - (order - 1) * 38, 0.5, 0),
			Size = UDim2.fromOffset(32, 32), BackgroundColor3 = color, Text = text,
			TextColor3 = Color3.new(1, 1, 1), TextSize = 16, Font = Enum.Font.GothamBlack,
			AutoButtonColor = true, ZIndex = 23,
		}, header)
		corner(b, 10)
		stroke(b, Color3.new(1, 1, 1), 1, 0.6)
		return b
	end
	UI.closeBtn = hdrButton("X", 1, Color3.fromRGB(200, 40, 70))
	UI.miniBtn = hdrButton("-", 2, Color3.fromRGB(30, 36, 90))

	local searchBox = new("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -92, 0.5, 0), Size = UDim2.fromOffset(190, 30),
		BackgroundColor3 = Color3.fromRGB(14, 16, 42), Text = "", PlaceholderText = "Search features...",
		PlaceholderColor3 = Color3.fromRGB(130, 140, 190), TextColor3 = Color3.new(1, 1, 1),
		TextSize = 12, Font = Enum.Font.GothamMedium, ClearTextOnFocus = false, ZIndex = 23,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, header)
	corner(searchBox, 10)
	accentGrad(stroke(searchBox, Color3.new(1, 1, 1), 1.4, 0.1), 0)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10) }, searchBox)

	-- sidebar -------------------------------------------------------------------------------
	local TABS = {
		{ "MOVE", "Movement", "M" }, { "PLAYER", "Player Utilities", "P" }, { "TELEPORT", "Teleport & Nav", "T" },
		{ "VISUAL", "Visual Effects", "V" }, { "CAMERA", "Camera Tools", "C" }, { "INFO", "Performance", "I" },
		{ "EXTRA", "Fun & Extras", "F" }, { "SHIELD", "Shield", "D" }, { "WEATHER", "Weather & Sky", "W" },
		{ "SAFETY", "Safety & Control", "S" }, { "TOOLS", "Settings", "G" },
		{ "FAV", "Favorites", "*" }, { "ABOUT", "About", "?" },
	}

	local side = new("ScrollingFrame", {
		Position = UDim2.fromOffset(8, HEAD + 6), Size = UDim2.fromOffset(SIDE, WH - HEAD - 62),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 20,
	}, win)
	new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, side)
	new("UIPadding", { PaddingRight = UDim.new(0, 4) }, side)

	local sideCard = new("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.fromOffset(SIDE, 46),
		BackgroundColor3 = Color3.fromRGB(14, 16, 40), BorderSizePixel = 0, ZIndex = 20,
	}, win)
	corner(sideCard, 12)
	accentGrad(stroke(sideCard, Color3.new(1, 1, 1), 1.4, 0.2), 0)
	lbl(sideCard, "AAYAN ADMIN V3", 11, Color3.new(1, 1, 1), Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21,
	})
	lbl(sideCard, "Enjoy Your Game!", 10, Color3.fromRGB(190, 170, 255), Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(0, 23), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21,
	})

	local tabBtns = {}

	-- content area -----------------------------------------------------------------------------
	local CX = SIDE + 16
	local CW = WW - CX - 8
	local statusBar = lbl(win, "ACTIVE: none", 10, Color3.fromRGB(140, 255, 200), Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(CX, HEAD + 4), Size = UDim2.fromOffset(CW, 14), ZIndex = 20,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local LIST_TOP = HEAD + 22
	local QH = 38
	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(CX, LIST_TOP), Size = UDim2.fromOffset(CW, WH - LIST_TOP - QH - 14),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 20,
	}, win)
	new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	new("UIPadding", { PaddingRight = UDim.new(0, 5), PaddingBottom = UDim.new(0, 4) }, list)

	local quick = new("Frame", {
		Position = UDim2.fromOffset(CX, WH - QH - 8), Size = UDim2.fromOffset(CW, QH),
		BackgroundColor3 = Color3.fromRGB(12, 14, 36), BorderSizePixel = 0, ZIndex = 20,
	}, win)
	corner(quick, 12)
	accentGrad(stroke(quick, Color3.new(1, 1, 1), 1.2, 0.35), 0)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5),
		VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, quick)

	local function applyQuickPlacement()
		if S.quickTop then
			quick.Position = UDim2.fromOffset(CX, LIST_TOP)
			list.Position = UDim2.fromOffset(CX, LIST_TOP + QH + 6)
			list.Size = UDim2.fromOffset(CW, WH - LIST_TOP - QH - 20)
		else
			quick.Position = UDim2.fromOffset(CX, WH - QH - 8)
			list.Position = UDim2.fromOffset(CX, LIST_TOP)
			list.Size = UDim2.fromOffset(CW, WH - LIST_TOP - QH - 14)
		end
	end

	--==============================================
	-- ROW SYSTEM
	--==============================================

	local rowCount = 0
	local dragSlider = nil

	local function baseRow(def, h)
		rowCount = rowCount + 1
		local fr = new("Frame", {
			Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = ROW, BackgroundTransparency = 0.1,
			BorderSizePixel = 0, LayoutOrder = rowCount, ZIndex = 21, Visible = false,
		}, list)
		corner(fr, 10)
		stroke(fr, Color3.fromRGB(70, 80, 160), 1, 0.55)
		local r = {
			frame = fr, cat = def.cat, sec = def.sec or "", id = def.id, kind = def.kind,
			key = (def.text .. " " .. def.cat .. " " .. def.id):lower(), refresh = function() end,
		}
		rows[#rows + 1] = r
		return r, fr
	end

	local function addStar(r, fr, h)
		local star = new("TextButton", {
			Position = UDim2.fromOffset(4, 0), Size = UDim2.fromOffset(20, h or S.rowH),
			BackgroundTransparency = 1, Text = "★", TextSize = 14, Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(80, 90, 140), ZIndex = 23,
		}, fr)
		local function paint()
			star.TextColor3 = favs[r.id] and Color3.fromRGB(255, 205, 70) or Color3.fromRGB(80, 90, 140)
		end
		bind(star.Activated, function()
			favs[r.id] = not favs[r.id] or nil
			paint()
			if curTab == "FAV" then F.refreshList() end
			notify(favs[r.id] and "Added to favorites" or "Removed from favorites", r.id, favs[r.id] and "on" or "off")
		end)
		paint()
		return star
	end

	local function textOf(def)
		return type(def.text) == "function" and def.text() or def.text
	end

	local function rowH() return S.rowH end

	local function HD(cat, sec)
		local def = { cat = cat, id = "hdr_" .. cat .. sec, text = sec, kind = "header" }
		local r, fr = baseRow(def, 24)
		fr.BackgroundTransparency = 1
		for _, c in ipairs(fr:GetChildren()) do if c:IsA("UIStroke") then c:Destroy() end end
		r.sec = sec
		local b = new("TextButton", {
			Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 22,
		}, fr)
		local t = lbl(fr, sec:upper(), 11, Color3.new(1, 1, 1), Enum.Font.GothamBlack, { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -40, 1, 0), ZIndex = 23 })
		accentGrad(t, 0)
		local arrow = lbl(fr, "v", 12, Color3.fromRGB(150, 170, 255), Enum.Font.GothamBlack, {
			Position = UDim2.new(1, -26, 0, 0), Size = UDim2.fromOffset(20, 24), ZIndex = 23, TextXAlignment = Enum.TextXAlignment.Center,
		})
		bind(b.Activated, function()
			local k = cat .. sec
			collapsed[k] = not collapsed[k] or nil
			arrow.Text = collapsed[k] and ">" or "v"
			F.refreshList()
		end)
		r.kind = "header"
		return r
	end

	local function T(cat, sec, id, text, get, set)
		local r, fr = baseRow({ cat = cat, sec = sec, id = id, text = text, kind = "toggle" }, rowH())
		r.dyn = true
		addStar(r, fr)
		local name = lbl(fr, text, 12, Color3.new(1, 1, 1), Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -120, 1, 0), ZIndex = 23, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local stat = lbl(fr, "OFF", 10, Color3.fromRGB(255, 110, 120), Enum.Font.GothamBlack, {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -56, 0.5, 0), Size = UDim2.fromOffset(34, 16),
			TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 23,
		})
		local pill = new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(38, 20),
			BackgroundColor3 = Color3.fromRGB(40, 44, 90), BorderSizePixel = 0, ZIndex = 23,
		}, fr)
		corner(pill, 10)
		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 24,
		}, pill)
		corner(knob, 7)
		local pg = nil
		local btnHit = new("TextButton", {
			Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -26, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 25,
		}, fr)
		r.refresh = function()
			local on = get()
			if on then
				stat.Text, stat.TextColor3 = "ON", Color3.fromRGB(90, 255, 150)
				pill.BackgroundColor3 = Color3.new(1, 1, 1)
				if not pg then pg = accentGrad(pill, 0) end
				knob.Position = UDim2.new(1, -17, 0.5, 0)
			else
				stat.Text, stat.TextColor3 = "OFF", Color3.fromRGB(255, 110, 120)
				pill.BackgroundColor3 = Color3.fromRGB(40, 44, 90)
				if pg then pg:Destroy() for i = #accents, 1, -1 do if accents[i] == pg then table.remove(accents, i) end end pg = nil end
				knob.Position = UDim2.new(0, 3, 0.5, 0)
			end
		end
		bind(btnHit.Activated, function()
			click()
			set(not get())
			notify(textOf({ text = text }), get() and "Enabled" or "Disabled", get() and "on" or "off")
			F.refreshAll()
		end)
		r.refresh()
		return r
	end

	local function SL(cat, sec, id, text, mn, mx, step, get, set, fmt)
		fmt = fmt or fmt0
		local r, fr = baseRow({ cat = cat, sec = sec, id = id, text = text, kind = "slider" }, 46)
		addStar(r, fr, 24)
		local name = lbl(fr, text, 12, Color3.new(1, 1, 1), Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(26, 3), Size = UDim2.new(0.6, -26, 0, 20), ZIndex = 23,
		})
		local val = lbl(fr, "", 12, Color3.fromRGB(150, 230, 255), Enum.Font.GothamBlack, {
			Position = UDim2.new(0.6, 0, 0, 3), Size = UDim2.new(0.4, -12, 0, 20), ZIndex = 23, TextXAlignment = Enum.TextXAlignment.Right,
		})
		local track = new("Frame", {
			Position = UDim2.new(0, 14, 0, 31), Size = UDim2.new(1, -28, 0, 6), BackgroundColor3 = Color3.fromRGB(34, 38, 84),
			BorderSizePixel = 0, ZIndex = 23,
		}, fr)
		corner(track, 3)
		local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 24 }, track)
		corner(fill, 3)
		accentGrad(fill, 0)
		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 25,
		}, track)
		corner(knob, 8)
		accentGrad(stroke(knob, Color3.new(1, 1, 1), 2, 0), 0)
		local hit = new("TextButton", {
			Position = UDim2.new(0, 6, 0, 22), Size = UDim2.new(1, -12, 0, 24), BackgroundTransparency = 1, Text = "", ZIndex = 26,
		}, fr)

		local function show(v)
			local a = math.clamp((v - mn) / (mx - mn), 0, 1)
			fill.Size = UDim2.new(a, 0, 1, 0)
			knob.Position = UDim2.new(a, 0, 0.5, 0)
			val.Text = fmt(v)
		end

		r.refresh = function() show(get()) end

		local function fromX(x)
			local a = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
			local v = mn + a * (mx - mn)
			v = math.floor(v / step + 0.5) * step
			v = math.clamp(v, mn, mx)
			show(v)
			set(v)
			F.updateStatus()
		end

		bind(hit.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragSlider = { fromX = fromX }
				list.ScrollingEnabled = false
				fromX(input.Position.X)
			end
		end)
		r.refresh()
		return r
	end

	local function BT(cat, sec, id, text, run, confirmBody)
		local r, fr = baseRow({ cat = cat, sec = sec, id = id, text = text, kind = "button" }, rowH())
		r.dyn = true
		addStar(r, fr)
		local name = lbl(fr, text, 12, Color3.new(1, 1, 1), Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -60, 1, 0), ZIndex = 23, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		lbl(fr, ">", 14, Color3.fromRGB(0, 220, 255), Enum.Font.GothamBlack, {
			Position = UDim2.new(1, -28, 0, 0), Size = UDim2.fromOffset(20, rowH()), ZIndex = 23, TextXAlignment = Enum.TextXAlignment.Center,
		})
		local b = new("TextButton", {
			Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -26, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 25,
		}, fr)
		bind(b.MouseButton1Down, function() tween(fr, 0.08, { BackgroundColor3 = Color3.fromRGB(40, 50, 110) }) end)
		bind(b.MouseButton1Up, function() tween(fr, 0.2, { BackgroundColor3 = ROW }) end)
		bind(b.MouseLeave, function() tween(fr, 0.2, { BackgroundColor3 = ROW }) end)
		bind(b.Activated, function()
			click()
			if confirmBody then
				confirm(text, confirmBody, function() run() F.refreshAll() end)
			else
				run()
				F.refreshAll()
			end
		end)
		return r
	end

	local function LB(cat, sec, id, text, live, h)
		local r, fr = baseRow({ cat = cat, sec = sec, id = id, text = text, kind = "label" }, h or 30)
		local name = lbl(fr, text, 11, Color3.fromRGB(150, 170, 230), Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 96, 0, 30), ZIndex = 23,
		})
		local v = lbl(fr, "", 12, Color3.new(1, 1, 1), Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(108, 0), Size = UDim2.new(1, -116, 1, 0), ZIndex = 23,
			TextWrapped = true, TextYAlignment = (h and h > 34) and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		})
		if h and h > 34 then v.Position = UDim2.fromOffset(10, 22) v.Size = UDim2.new(1, -20, 1, -24) name.Size = UDim2.new(1, -20, 0, 20) name.Position = UDim2.fromOffset(10, 2) end
		r.refresh = function()
			local ok, res = pcall(live)
			v.Text = ok and tostring(res) or "n/a"
		end
		r.live = true
		return r
	end

	-- free-form row. build(frame) fills it. auto = height follows content
	local function CU(cat, sec, id, text, h, build, auto)
		local r, fr = baseRow({ cat = cat, sec = sec, id = id, text = text, kind = "custom" }, h)
		if auto then
			fr.AutomaticSize = Enum.AutomaticSize.Y
			fr.Size = UDim2.new(1, 0, 0, h)
		end
		addStar(r, fr, 22)
		lbl(fr, text, 12, Color3.new(1, 1, 1), Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(26, 3), Size = UDim2.new(1, -36, 0, 18), ZIndex = 23,
		})
		build(fr, r)
		return r
	end

	local function miniBtn(parent, text, size, pos, cb, color)
		local b = new("TextButton", {
			Position = pos, Size = size, BackgroundColor3 = color or Color3.fromRGB(32, 40, 96), Text = text,
			TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = Enum.Font.GothamBold, AutoButtonColor = true, ZIndex = 26,
		}, parent)
		corner(b, 8)
		stroke(b, Color3.new(1, 1, 1), 1, 0.7)
		bind(b.Activated, function() click() cb() F.refreshAll() end)
		return b
	end

	local function textBox(parent, placeholder, size, pos)
		local tb = new("TextBox", {
			Position = pos, Size = size, BackgroundColor3 = Color3.fromRGB(12, 14, 36), Text = "",
			PlaceholderText = placeholder, PlaceholderColor3 = Color3.fromRGB(120, 130, 180), TextColor3 = Color3.new(1, 1, 1),
			TextSize = 11, Font = Enum.Font.GothamMedium, ClearTextOnFocus = false, ZIndex = 26,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, parent)
		corner(tb, 8)
		stroke(tb, CYAN, 1, 0.5)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, tb)
		return tb
	end

	--==============================================
	-- LIST / TAB / STATUS REFRESH
	--==============================================

	function F.refreshList()
		local q = (S.search or ""):lower()
		for _, r in ipairs(rows) do
			local vis
			if q ~= "" then
				vis = r.kind ~= "header" and r.key:find(q, 1, true) ~= nil
			elseif curTab == "FAV" then
				vis = r.kind ~= "header" and favs[r.id] == true
			else
				vis = (r.cat == curTab) and (r.kind == "header" or not collapsed[r.cat .. r.sec])
			end
			r.frame.Visible = vis
		end
	end

	function F.refreshAll()
		for _, r in ipairs(rows) do
			if r.frame.Visible then pcall(r.refresh) end
		end
		F.updateStatus()
	end

	function F.setTab(id)
		curTab = id
		S.search = ""
		searchBox.Text = ""
		for k, b in pairs(tabBtns) do
			local on = (k == id)
			b.sel.Visible = on
			b.label.TextColor3 = on and Color3.new(1, 1, 1) or Color3.fromRGB(190, 200, 240)
		end
		F.refreshList()
		list.CanvasPosition = Vector2.zero
		F.refreshAll()
	end

	for i, t in ipairs(TABS) do
		local b = new("TextButton", {
			LayoutOrder = i, Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(18, 22, 52),
			BackgroundTransparency = 0.1, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 21,
		}, side)
		corner(b, 9)
		local sel = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Visible = false, ZIndex = 21 }, b)
		corner(sel, 9)
		accentGrad(sel, 0)
		local ic = new("Frame", {
			Position = UDim2.fromOffset(6, 5), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Color3.fromRGB(30, 36, 86), BorderSizePixel = 0, ZIndex = 22,
		}, b)
		corner(ic, 6)
		lbl(ic, t[3], 11, Color3.new(1, 1, 1), Enum.Font.GothamBlack, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })
		local l = lbl(b, t[2], 11, Color3.fromRGB(190, 200, 240), Enum.Font.GothamBold, {
			Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -34, 1, 0), ZIndex = 23, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		tabBtns[t[1]] = { sel = sel, label = l }
		bind(b.Activated, function() click() F.setTab(t[1]) end)
	end

	bind(searchBox:GetPropertyChangedSignal("Text"), function()
		S.search = searchBox.Text
		F.refreshList()
	end)

	function F.updateStatus()
		local t = F.status()
		statusBar.Text = "ACTIVE: " .. (#t > 0 and table.concat(t, "  ·  ") or "none")
		if F.refreshQuick then F.refreshQuick() end
	end

	--==============================================
	-- GUI SETTINGS APPLY
	--==============================================

	S.search = ""
	local previewModel, previewVp
	local respawns = 0
	local fpsValue, fpsCount, fpsTimer = 60, 0, 0
	local liveTimer, rgbTimer, rgbHue = 0, 0, 0
	local isOpen = false
	local minimized = false
	local busy = 0

	function F.applyGui()
		fitScale()
		win.BackgroundTransparency = S.bgTrans
		for _, r in ipairs(rows) do
			if r.dyn then r.frame.Size = UDim2.new(1, 0, 0, S.rowH) end
		end
		applyQuickPlacement()
		F.refreshAll()
	end

	function F.applyPerf()
		if S.perf then S.rgb = false end
		F.rebuildFx()
		notify("Performance mode", S.perf and "Lighter effects" or "Full effects", S.perf and "on" or "off")
	end

	--==============================================
	-- FEATURE ROWS
	--==============================================

	local function tgl(key) return function() return S[key] end, function(v) S[key] = v end end

	-- MOVEMENT ------------------------------------------------------------------------------------------
	HD("MOVE", "Flight")
	T("MOVE", "Flight", "fly", "Fly", function() return S.fly end, F.setFly)
	SL("MOVE", "Flight", "flyspeed", "Fly speed", 10, 250, 5, function() return S.flySpeed end, function(v) S.flySpeed = v end)
	T("MOVE", "Flight", "camrel", "Camera-relative movement", tgl("camRel"))
	T("MOVE", "Flight", "pad", "Up / Down pad (touch)", tgl("pad"))

	HD("MOVE", "Walking & Jumping")
	T("MOVE", "Walking & Jumping", "noclip", "Noclip", function() return S.noclip end, F.setNoclip)
	SL("MOVE", "Walking & Jumping", "walk", "Walk speed", 8, 200, 1, function() return S.walkOn and S.walk or Def.walk end, F.setWalk)
	SL("MOVE", "Walking & Jumping", "jump", "Jump power", 20, 300, 5, function() return S.jumpOn and S.jump or Def.jump end, F.setJump)
	T("MOVE", "Walking & Jumping", "infjump", "Infinite jump", tgl("infJump"))
	T("MOVE", "Walking & Jumping", "sprint", "Sprint (x1.6)", tgl("sprint"))
	BT("MOVE", "Walking & Jumping", "dash", "Dash", F.dash)
	T("MOVE", "Walking & Jumping", "air", "Air movement control", tgl("airCtl"))
	T("MOVE", "Walking & Jumping", "slowfall", "Slow fall", tgl("slowFall"))

	HD("MOVE", "Rotation & Reset")
	T("MOVE", "Rotation & Reset", "autorot", "Auto rotate", function() return S.autoRotate end, function(v)
		S.autoRotate = v
		local h = getHum()
		if h then h.AutoRotate = v end
	end)
	SL("MOVE", "Rotation & Reset", "yaw", "Character rotation", 0, 360, 5, function() return S.yaw end, F.setYaw)
	BT("MOVE", "Rotation & Reset", "movereset", "Reset movement", function()
		F.restoreWalk() F.restoreJump() S.yaw = 0
		notify("Movement reset", nil, "on")
	end)
	BT("MOVE", "Rotation & Reset", "movestop", "Emergency movement stop", F.stopAll)

	-- PLAYER --------------------------------------------------------------------------------------------
	HD("PLAYER", "Character")
	BT("PLAYER", "Character", "resetchar", "Reset character", function()
		local h = getHum()
		if h then h.Health = 0 end
	end, "Your character will respawn. Continue?")
	BT("PLAYER", "Character", "spawn", "Return to spawn", function()
		local cf = F.spawnPoint()
		if cf then F.tp(cf, "Return to spawn") else notify("Spawn", "No spawn point found", "warn") end
	end)
	LB("PLAYER", "Character", "coords", "Coordinates", function()
		local r = getRoot()
		return r and v3s(r.Position) or "-"
	end)
	LB("PLAYER", "Character", "pinfo", "Player info", function()
		return string.format("%s (@%s)\nID %d  ·  Account age %d days", player.DisplayName, player.Name, player.UserId, player.AccountAge)
	end, 56)
	LB("PLAYER", "Character", "health", "Health", function()
		local h = getHum()
		return h and (fmt0(h.Health) .. " / " .. fmt0(h.MaxHealth)) or "-"
	end)
	LB("PLAYER", "Character", "state", "State", function()
		local h = getHum()
		return h and tostring(h:GetState()):gsub("Enum.HumanoidStateType.", "") or "-"
	end)

	HD("PLAYER", "Camera & Spectate")
	BT("PLAYER", "Camera & Spectate", "zoomin", "Camera zoom in", function() F.zoomBy(-6) end)
	BT("PLAYER", "Camera & Spectate", "zoomout", "Camera zoom out", function() F.zoomBy(6) end)
	T("PLAYER", "Camera & Spectate", "firstp", "First person", function() return player.CameraMode == Enum.CameraMode.LockFirstPerson end, F.setFirst)
	BT("PLAYER", "Camera & Spectate", "thirdp", "Third person", F.thirdPerson)
	CU("PLAYER", "Camera & Spectate", "spectate", "Spectator camera", 64, function(fr)
		local tb = textBox(fr, "Player name...", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 26))
		miniBtn(fr, "SPECTATE", UDim2.new(0.5, -14, 0, 24), UDim2.new(0, 10, 0, 56 - 0), function() F.spectate(tb.Text) end).Position = UDim2.new(0, 10, 0, 56)
		miniBtn(fr, "STOP", UDim2.new(0.5, -14, 0, 24), UDim2.new(0.5, 4, 0, 56), F.stopSpectate)
		fr.Size = UDim2.new(1, 0, 0, 86)
	end)

	-- TELEPORT --------------------------------------------------------------------------------------------
	HD("TELEPORT", "Waypoints")
	BT("TELEPORT", "Waypoints", "savewp", "Save waypoint", F.saveWp)
	BT("TELEPORT", "Waypoints", "tpwp", "Teleport to selected waypoint", function() F.tpWp(S.selWp) end)
	BT("TELEPORT", "Waypoints", "prevpos", "Return to previous position", function()
		if prevCF then F.tp(prevCF, "Previous position") else notify("Previous position", "Nothing stored yet", "warn") end
	end)
	local wpRow = CU("TELEPORT", "Waypoints", "wplist", "Waypoint list", 52, function(fr, r)
		r.box = new("Frame", { Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 1, -30), BackgroundTransparency = 1, ZIndex = 24 }, fr)
		new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, r.box)
	end)
	function F.rebuildWpList()
		local box = wpRow.box
		for _, c in ipairs(box:GetChildren()) do
			if not c:IsA("UIListLayout") then c:Destroy() end
		end
		if #wps == 0 then
			lbl(box, "No waypoints saved yet.", 11, Color3.fromRGB(130, 140, 190), Enum.Font.Gotham, { Size = UDim2.new(1, 0, 0, 20), ZIndex = 25 })
			wpRow.frame.Size = UDim2.new(1, 0, 0, 52)
			return
		end
		for i, w in ipairs(wps) do
			local line = new("Frame", {
				LayoutOrder = i, Size = UDim2.new(1, 0, 0, 26), BorderSizePixel = 0, ZIndex = 25,
				BackgroundColor3 = (i == S.selWp) and Color3.fromRGB(40, 56, 130) or Color3.fromRGB(14, 16, 40),
			}, box)
			corner(line, 7)
			local pick = new("TextButton", {
				Size = UDim2.new(1, -90, 1, 0), BackgroundTransparency = 1, ZIndex = 26, TextSize = 11, Font = Enum.Font.GothamBold,
				TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
				Text = "  " .. w.name .. "   " .. v3s(w.cf.Position),
			}, line)
			pick.TextTruncate = Enum.TextTruncate.AtEnd
			bind(pick.Activated, function() click() S.selWp = i F.rebuildWpList() F.updateMarkers() end)
			miniBtn(line, "TP", UDim2.fromOffset(34, 20), UDim2.new(1, -84, 0, 3), function() F.tpWp(i) end)
			miniBtn(line, "CP", UDim2.fromOffset(24, 20), UDim2.new(1, -46, 0, 3), function()
				F.copyText(v3s(w.cf.Position), w.name)
			end)
			miniBtn(line, "X", UDim2.fromOffset(18, 20), UDim2.new(1, -20, 0, 3), function() F.delWp(i) end, Color3.fromRGB(150, 40, 70))
		end
		wpRow.frame.Size = UDim2.new(1, 0, 0, 34 + #wps * 29)
	end
	F.rebuildWpList()

	HD("TELEPORT", "Navigation")
	LB("TELEPORT", "Navigation", "coords2", "Coordinates", function()
		local r = getRoot()
		return r and v3s(r.Position) or "-"
	end)
	LB("TELEPORT", "Navigation", "distance", "Distance to WP", function()
		local d = F.distToSel()
		return d and (fmt1(d) .. " studs  (" .. wps[S.selWp].name .. ")") or "select a waypoint"
	end)
	T("TELEPORT", "Navigation", "markers", "Map markers", function() return S.markers end, function(v) S.markers = v F.updateMarkers() end)
	T("TELEPORT", "Navigation", "navigate", "Navigation arrow (camera)", tgl("navigate"))
	BT("TELEPORT", "Navigation", "setspawn", "Set configured spawn here", function()
		local r = getRoot()
		if r then spawnCF = r.CFrame notify("Spawn configured", v3s(r.Position), "on") end
	end)
	BT("TELEPORT", "Navigation", "tpspawn", "Teleport to configured spawn", function()
		if spawnCF then F.tp(spawnCF, "Configured spawn") else notify("Spawn", "Set a spawn first", "warn") end
	end)
	BT("TELEPORT", "Navigation", "copycoord", "Copy coordinates", function()
		local r = getRoot()
		if r then F.copyText(v3s(r.Position), "coordinates") end
	end)
	BT("TELEPORT", "Navigation", "copywp", "Copy selected waypoint", function()
		local w = wps[S.selWp]
		if w then F.copyText(v3s(w.cf.Position), w.name) else notify("Waypoint", "Nothing selected", "warn") end
	end)
	BT("TELEPORT", "Navigation", "clearwp", "Clear all waypoints", F.clearWps, "Delete every saved waypoint?")

	-- VISUAL ---------------------------------------------------------------------------------------------
	HD("VISUAL", "Effects")
	T("VISUAL", "Effects", "aura", "Aura", function() return S.aura end, function(v) S.aura = v F.rebuildFx() end)
	BT("VISUAL", "Effects", "aurapreset", "Aura preset (next)", function()
		S.auraIdx = S.auraIdx % #AURAS + 1
		F.rebuildFx()
		notify("Aura: " .. AURAS[S.auraIdx][1], nil, "on")
	end)
	LB("VISUAL", "Effects", "auraname", "Current preset", function() return AURAS[S.auraIdx][1] end)
	T("VISUAL", "Effects", "particles", "Particle effects", function() return S.particles end, function(v) S.particles = v F.rebuildFx() end)
	T("VISUAL", "Effects", "trail", "Character trail", function() return S.trail end, function(v) S.trail = v F.rebuildFx() end)
	T("VISUAL", "Effects", "neon", "Neon colour effect", function() return S.neon end, function(v) S.neon = v F.rebuildFx() end)
	SL("VISUAL", "Effects", "fx", "Effects intensity", 0, 1, 0.05, function() return S.fx end, function(v) S.fx = v F.updateFx() end, fmt1)
	BT("VISUAL", "Effects", "clearfx", "Clear visual effects", function() F.clearFx() notify("Effects cleared", nil, "off") end)

	HD("VISUAL", "Emotes (default Roblox)")
	CU("VISUAL", "Emotes (default Roblox)", "emotes", "Approved emotes", 96, function(fr)
		local names = { "wave", "point", "cheer", "laugh", "dance", "dance2", "dance3" }
		for i, n in ipairs(names) do
			local col = (i - 1) % 4
			local rowi = math.floor((i - 1) / 4)
			miniBtn(fr, n:upper(), UDim2.new(0.25, -9, 0, 24), UDim2.new(0.25 * col, 8, 0, 28 + rowi * 30), function() F.emote(n) end)
		end
		miniBtn(fr, "STOP", UDim2.new(0.25, -9, 0, 24), UDim2.new(0.75, 8, 0, 58), F.stopEmote, Color3.fromRGB(150, 40, 70))
	end)

	HD("VISUAL", "Preview & Theme")
	CU("VISUAL", "Preview & Theme", "preview", "Character preview", 132, function(fr)
		previewVp = new("ViewportFrame", {
			Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -20, 0, 98), BackgroundColor3 = Color3.fromRGB(10, 12, 30),
			BorderSizePixel = 0, ZIndex = 26,
		}, fr)
		corner(previewVp, 10)
		previewVp.CurrentCamera = new("Camera", { CFrame = CFrame.new(Vector3.new(0, 1.2, 7.5), Vector3.new(0, 0.4, 0)) }, previewVp)
	end)
	function F.refreshPreview()
		if not previewVp then return end
		if previewModel then previewModel:Destroy() previewModel = nil end
		local ch = getChar()
		if not ch then return end
		ch.Archivable = true
		local ok, clone = pcall(function() return ch:Clone() end)
		if not ok or not clone then return end
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BaseScript") or d:IsA("Highlight") or d:IsA("ParticleEmitter") or d:IsA("Trail") then d:Destroy() end
		end
		local r = clone:FindFirstChild("HumanoidRootPart")
		if r then r.Anchored = true end
		clone.Parent = previewVp
		clone:PivotTo(CFrame.new(0, 0, 0))
		previewModel = clone
	end
	CU("VISUAL", "Preview & Theme", "accent", "GUI accent colour", 78, function(fr)
		for i, a in ipairs(AURAS) do
			local sw = new("TextButton", {
				Position = UDim2.new(0, 10 + ((i - 1) % 8) * 40, 0, 28 + math.floor((i - 1) / 8) * 30),
				Size = UDim2.fromOffset(34, 24), BackgroundColor3 = Color3.new(1, 1, 1), Text = "", ZIndex = 26,
			}, fr)
			corner(sw, 8)
			new("UIGradient", { Color = ColorSequence.new(a[2], a[3]), Rotation = 45 }, sw)
			stroke(sw, Color3.new(1, 1, 1), 1, 0.5)
			bind(sw.Activated, function()
				click()
				Theme.A1, Theme.A2 = a[2], a[3]
				S.rgb = false
				applyTheme()
				notify("Accent: " .. a[1], nil, "on")
				F.refreshAll()
			end)
		end
	end)
	T("VISUAL", "Preview & Theme", "rgb", "RGB theme", function() return S.rgb end, function(v) S.rgb = v and not S.perf end)

	-- CAMERA --------------------------------------------------------------------------------------------
	HD("CAMERA", "Controls")
	SL("CAMERA", "Controls", "sens", "Camera sensitivity", 0.1, 3, 0.1, function() return S.sens end, F.setSens, fmt1)
	SL("CAMERA", "Controls", "fov", "Camera FOV", 40, 120, 1, function() return S.fovOn and S.fov or (cam() and cam().FieldOfView or 70) end, F.setFov)
	SL("CAMERA", "Controls", "zoom", "Zoom distance", 1, 100, 1, function() return S.zoom end, function(v) S.zoom = v F.zoomTo(v) end)
	T("CAMERA", "Controls", "smooth", "Smooth camera", function() return S.smooth end, F.setSmooth)
	T("CAMERA", "Controls", "lock", "Camera lock", function() return S.lock end, F.setLock)
	T("CAMERA", "Controls", "free", "Free camera", function() return S.free end, F.setFree)
	BT("CAMERA", "Controls", "camreset", "Camera reset", function() F.resetCamera() notify("Camera reset", nil, "on") end)
	BT("CAMERA", "Controls", "camdefaults", "Restore default camera settings", function() F.resetCamera() notify("Camera defaults restored", nil, "on") end)
	HD("CAMERA", "Readout")
	LB("CAMERA", "Readout", "campos", "Camera position", function() return cam() and v3s(cam().CFrame.Position) or "-" end)
	LB("CAMERA", "Readout", "camrot", "Camera rotation", function()
		local c = cam()
		if not c then return "-" end
		local x, y, z = c.CFrame:ToOrientation()
		return string.format("%.0f, %.0f, %.0f deg", math.deg(x), math.deg(y), math.deg(z))
	end)

	-- PERFORMANCE & INFO --------------------------------------------------------------------------
	HD("INFO", "Live stats")
	LB("INFO", "Live stats", "fps", "FPS", function() return fmt0(fpsValue) end)
	LB("INFO", "Live stats", "ping", "Ping", function()
		local ok, v = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
		return ok and (fmt0(v) .. " ms") or "not available"
	end)
	LB("INFO", "Live stats", "mem", "Client memory", function()
		local ok, v = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
		return ok and (fmt0(v) .. " MB") or "not available"
	end)
	LB("INFO", "Live stats", "timer", "Session timer", function()
		local t = math.floor(os.clock() - startClock)
		return string.format("%02d:%02d:%02d", math.floor(t / 3600), math.floor(t / 60) % 60, t % 60)
	end)
	LB("INFO", "Live stats", "players", "Players in server", function() return tostring(#Players:GetPlayers()) .. " / " .. tostring(Players.MaxPlayers) end)
	LB("INFO", "Live stats", "posmon", "Position monitor", function()
		local r = getRoot()
		return r and (v3s(r.Position) .. "   speed " .. fmt1(r.AssemblyLinearVelocity.Magnitude)) or "-"
	end)
	LB("INFO", "Live stats", "movemon", "Movement status", function()
		local t = F.status()
		return #t > 0 and table.concat(t, ", ") or "idle"
	end)

	HD("INFO", "Players & performance")
	CU("INFO", "Players & performance", "plist", "Player list search", 112, function(fr, r)
		local tb = textBox(fr, "Search player...", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 26))
		local out = lbl(fr, "", 11, Color3.new(1, 1, 1), Enum.Font.Gotham, {
			Position = UDim2.fromOffset(12, 56), Size = UDim2.new(1, -24, 1, -60), ZIndex = 26,
			TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		})
		local function update()
			local q = tb.Text:lower()
			local lines = {}
			local me = getRoot()
			for _, p in ipairs(Players:GetPlayers()) do
				if q == "" or p.Name:lower():find(q, 1, true) or p.DisplayName:lower():find(q, 1, true) then
					local pr = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					local d = (pr and me) and (fmt0((pr.Position - me.Position).Magnitude) .. " studs") or "-"
					lines[#lines + 1] = p.DisplayName .. " (@" .. p.Name .. ")  " .. d
					if #lines >= 6 then break end
				end
			end
			out.Text = #lines > 0 and table.concat(lines, "\n") or "No match."
		end
		bind(tb:GetPropertyChangedSignal("Text"), update)
		r.refresh = update
	end)
	T("INFO", "Players & performance", "perf", "Performance-friendly effects", function() return S.perf end, function(v) S.perf = v F.applyPerf() end)
	BT("INFO", "Players & performance", "reinit", "Reinitialize local GUI", function()
		notify("Reinitializing GUI", nil, "warn")
		task.defer(function() _G.AAYAN_ADMIN_SHUTDOWN() Boot() end)
	end)

	-- FUN & EXTRAS --------------------------------------------------------------------------------------
	HD("EXTRA", "Movement presets")
	CU("EXTRA", "Movement presets", "presets", "Custom movement presets", 66, function(fr)
		local names = { "NORMAL", "RUNNER", "MOON", "SPEEDY", "FLYER" }
		for i, n in ipairs(names) do
			miniBtn(fr, n, UDim2.new(0.2, -7, 0, 26), UDim2.new(0.2 * (i - 1), 6, 0, 30), function() F.applyPreset(n) end)
		end
	end)
	BT("EXTRA", "Movement presets", "savetemp", "Save temporary settings (memory only)", F.saveTemp)
	BT("EXTRA", "Movement presets", "loadtemp", "Load temporary preset", F.loadTemp)
	BT("EXTRA", "Movement presets", "restoreall", "Restore all supported defaults", F.restoreDefaults)
	HD("EXTRA", "Session activity")
	LB("EXTRA", "Session activity", "history", "Session-only history", function()
		if #history == 0 then return "Nothing yet." end
		local t = {}
		for i = 1, math.min(7, #history) do t[i] = history[i] end
		return table.concat(t, "\n")
	end, 130)

	-- SAFETY & CONTROL ---------------------------------------------------------------------------------
	HD("SAFETY", "Stop / restore")
	BT("SAFETY", "Stop / restore", "stopall", "STOP ALL active local effects", F.stopAll)
	BT("SAFETY", "Stop / restore", "rwalk", "Restore default WalkSpeed", function() F.restoreWalk() notify("WalkSpeed restored", tostring(Def.walk), "on") end)
	BT("SAFETY", "Stop / restore", "rjump", "Restore default JumpPower", function() F.restoreJump() notify("JumpPower restored", tostring(Def.jump), "on") end)
	BT("SAFETY", "Stop / restore", "rcam", "Restore default camera settings", function() F.resetCamera() notify("Camera restored", nil, "on") end)
	BT("SAFETY", "Stop / restore", "rcol", "Restore collision settings", function() F.restoreCollision() S.noclip = false notify("Collision restored", "Where permitted", "on") end)
	BT("SAFETY", "Stop / restore", "emergency", "EMERGENCY RESET", F.emergency, "Revert every local change (movement, camera, effects, markers)?")
	HD("SAFETY", "System")
	LB("SAFETY", "System", "respawn", "Respawn detection", function() return "ON  ·  respawns seen: " .. respawns end)
	BT("SAFETY", "System", "reinitmove", "Reinitialize movement controls", function()
		F.stopFly() F.restoreCollision() walkApplied, jumpApplied = false, false
		F.applyHum()
		notify("Movement controls reinitialized", nil, "on")
	end)
	LB("SAFETY", "System", "loops", "Update loops", function() return "Heartbeat 1 · Stepped 1 · RenderStep 1 (no duplicates)" end)
	BT("SAFETY", "System", "shutdown", "Clean up connections & close hub", function()
		task.defer(function() _G.AAYAN_ADMIN_SHUTDOWN() end)
	end, "Close AAYAN ADMIN completely and disconnect everything?")

	-- SETTINGS / TOOLS -------------------------------------------------------------------------------------
	HD("TOOLS", "Convenience")
	BT("TOOLS", "Convenience", "rejoin", "Rejoin current experience", function()
		pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
	end, "Rejoin this experience now?")
	BT("TOOLS", "Convenience", "hideui", "Toggle interface visibility", function()
		F.setOpen(false)
		notify("Interface hidden", "Use the left toggle or RightCtrl", "warn")
	end)
	BT("TOOLS", "Convenience", "copyc", "Copy coordinates", function()
		local r = getRoot()
		if r then F.copyText(v3s(r.Position), "coordinates") end
	end)
	BT("TOOLS", "Convenience", "copyw", "Copy waypoint coordinates", function()
		local w = wps[S.selWp]
		if w then F.copyText(v3s(w.cf.Position), w.name) else notify("Waypoint", "Nothing selected", "warn") end
	end)
	HD("TOOLS", "Interface")
	SL("TOOLS", "Interface", "scale", "UI scale", 0.6, 1.4, 0.05, function() return S.scale end, function(v) S.scale = v fitScale() end, fmt1)
	SL("TOOLS", "Interface", "trans", "Panel transparency", 0, 0.6, 0.05, function() return S.bgTrans end, function(v) S.bgTrans = v win.BackgroundTransparency = v end, fmt1)
	SL("TOOLS", "Interface", "rowh", "Button size", 30, 54, 2, function() return S.rowH end, function(v) S.rowH = v F.applyGui() end)
	T("TOOLS", "Interface", "sfx", "Sound effects", tgl("sfx"))
	T("TOOLS", "Interface", "reduce", "Reduce animations", tgl("reduceAnim"))
	T("TOOLS", "Interface", "quicktop", "Quick bar on top (mobile)", function() return S.quickTop end, function(v) S.quickTop = v applyQuickPlacement() end)
	T("TOOLS", "Interface", "server", "Server-authorised mode (own game)", function() return S.serverMode end, function(v)
		if v and not remote() then
			notify("Server mode", "AAYAN_ADMIN_REMOTE not found in ReplicatedStorage", "warn")
			S.serverMode = false
		else
			S.serverMode = v
		end
	end)
	BT("TOOLS", "Interface", "resetgui", "Reset GUI settings", function()
		for k, v in pairs(DEFAULT_GUI) do S[k] = v end
		Theme.A1, Theme.A2 = CYAN, PURPLE
		applyTheme()
		F.applyGui()
		notify("GUI settings reset", nil, "on")
	end)


	-- SHIELD (30) -----------------------------------------------------------------------------------------
	HD("SHIELD", "Overview")
	LB("SHIELD", "Overview", "shcount", "Active shields", function() return F.shieldCount() .. " / 30 active" end)
	BT("SHIELD", "Overview", "shrec", "Recommended shield set", F.recommendedShields)
	BT("SHIELD", "Overview", "shall", "ALL 30 SHIELDS ON", function() F.allShields(true) end)
	BT("SHIELD", "Overview", "shnone", "ALL SHIELDS OFF", function() F.allShields(false) end)
	do
		local lastGroup
		for _, d in ipairs(F.SHIELDS) do
			if d[3] ~= lastGroup then HD("SHIELD", d[3]) lastGroup = d[3] end
			T("SHIELD", d[3], "sh_" .. d[1], d[2], function() return Sh[d[1]] == true end, function(v) F.setShield(d[1], v) end)
		end
	end

	-- WEATHER & SKY (13) -----------------------------------------------------------------------------------
	HD("WEATHER", "13 modes (stay on until you stop them)")
	for _, d in ipairs(W.names) do
		T("WEATHER", "13 modes (stay on until you stop them)", "w_" .. d[1], d[2], function() return W.active == d[1] end, function(v)
			if v then W.start(d[1]) else W.stop() end
		end)
	end
	BT("WEATHER", "13 modes (stay on until you stop them)", "wstop", "Stop weather (restore game sky)", function() W.stop() end)
	LB("WEATHER", "13 modes (stay on until you stop them)", "wnow", "Current mode", function() return W.active or "none" end)

	-- ABOUT -----------------------------------------------------------------------------------------------------
	LB("ABOUT", "", "ver", "Version", function() return "AAYAN ADMIN V3  ·  " .. VERSION end)
	BT("ABOUT", "", "help", "Help & controls", function()
		infoModal("HELP & CONTROLS",
			"FLY: WASD / joystick, Space or E up, Shift or Q down (touch: UP/DOWN pad).\n" ..
			"FREE CAM: same keys, hold right mouse or drag to look.\n" ..
			"RightCtrl: show / hide the hub.\n" ..
			"Star on a row = favourite (see Favorites tab).\n" ..
			"Search box filters every feature.\n" ..
			"STOP ALL / EMERGENCY RESET revert everything local.", 250)
	end)
	BT("ABOUT", "", "version", "Version information", function()
		infoModal("VERSION " .. VERSION,
			"AAYAN ADMIN V3 · Ultimate Universal Control Hub.\n" ..
			"Client-side only. Optional server script: AAYAN_ADMIN_V3_Server.lua (for your own game).", 190)
	end)
	LB("ABOUT", "", "limits", "Limitations", function()
		return "Fly / noclip / speed / teleport are local: a game's server or anti-cheat may override or block them. Clipboard needs setclipboard. Emotes need R15. Free camera depends on the game camera."
	end, 100)

	--==============================================
	-- QUICK TOOLBAR
	--==============================================

	local qDefs = {
		{ "FLY", function() F.setFly(not S.fly) end, function() return S.fly end },
		{ "NOCLIP", function() F.setNoclip(not S.noclip) end, function() return S.noclip end },
		{ "SPRINT", function() S.sprint = not S.sprint end, function() return S.sprint end },
		{ "DASH", F.dash, function() return false end },
		{ "STOP ALL", F.stopAll, function() return false end, Color3.fromRGB(170, 36, 70) },
		{ "RESET", F.emergency, function() return false end, Color3.fromRGB(120, 60, 170) },
	}
	local qBtns = {}
	do
		local w = math.floor((CW - 12 - 5 * 5) / 6)
		for i, d in ipairs(qDefs) do
			local b = new("TextButton", {
				LayoutOrder = i, Size = UDim2.fromOffset(w, 26), BackgroundColor3 = d[4] or Color3.fromRGB(28, 34, 84),
				Text = d[1], TextColor3 = Color3.new(1, 1, 1), TextSize = 10, Font = Enum.Font.GothamBlack,
				AutoButtonColor = true, ZIndex = 22,
			}, quick)
			corner(b, 8)
			bind(b.Activated, function()
				click()
				d[2]()
				if i <= 3 then notify(d[1], d[3]() and "Enabled" or "Disabled", d[3]() and "on" or "off") end
				F.refreshAll()
			end)
			qBtns[i] = b
		end
	end
	function F.refreshQuick()
		for i, d in ipairs(qDefs) do
			if not d[4] then
				qBtns[i].BackgroundColor3 = d[3]() and Color3.fromRGB(0, 140, 190) or Color3.fromRGB(28, 34, 84)
			end
		end
	end

	--==============================================
	-- FLY PAD + NAV HUD
	--==============================================

	local pad = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 70), Size = UDim2.fromOffset(60, 110),
		BackgroundTransparency = 1, Visible = false, ZIndex = 60,
	}, sg)
	for i, d in ipairs({ { "UP", "up" }, { "DOWN", "down" } }) do
		local b = new("TextButton", {
			Position = UDim2.fromOffset(0, (i - 1) * 58), Size = UDim2.fromOffset(60, 50),
			BackgroundColor3 = Color3.fromRGB(14, 18, 44), BackgroundTransparency = 0.1, Text = d[1],
			TextColor3 = Color3.new(1, 1, 1), TextSize = 13, Font = Enum.Font.GothamBlack, AutoButtonColor = false, ZIndex = 61,
		}, pad)
		corner(b, 14)
		accentGrad(stroke(b, Color3.new(1, 1, 1), 2, 0), 0)
		bind(b.MouseButton1Down, function() S[d[2]] = true end)
		bind(b.MouseButton1Up, function() S[d[2]] = false end)
		bind(b.MouseLeave, function() S[d[2]] = false end)
	end

	local nav = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(150, 50),
		BackgroundColor3 = NAVY, BackgroundTransparency = 0.15, BorderSizePixel = 0, Visible = false, ZIndex = 60,
	}, sg)
	corner(nav, 14)
	accentGrad(stroke(nav, Color3.new(1, 1, 1), 1.6, 0), 0)
	local navArrow = lbl(nav, "^", 26, CYAN, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(40, 42), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 61,
	})
	local navText = lbl(nav, "", 11, Color3.new(1, 1, 1), Enum.Font.GothamBold, {
		Position = UDim2.fromOffset(54, 0), Size = UDim2.new(1, -58, 1, 0), ZIndex = 61, TextWrapped = true,
	})

	--==============================================
	-- LEFT TOGGLE (draggable)
	--==============================================

	local toggle = new("TextButton", {
		Name = "Toggle", Position = UDim2.new(0, 10, 0.5, 4), Size = UDim2.fromOffset(60, 84),
		BackgroundColor3 = Color3.fromRGB(12, 14, 36), Text = "", AutoButtonColor = false, ZIndex = 70,
	}, sg)
	corner(toggle, 16)
	local toggleStroke = stroke(toggle, Color3.new(1, 1, 1), 2.6, 0)
	local toggleGrad = accentGrad(toggleStroke, 0)
	crown(toggle, 12, 8, 1.05, 71)
	lbl(toggle, "AAYAN", 11, Color3.new(1, 1, 1), Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 71,
	})
	lbl(toggle, "ADMIN", 11, Color3.new(1, 1, 1), Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(0, 53), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 71,
	})
	lbl(toggle, ">>", 13, CYAN, Enum.Font.GothamBlack, {
		Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 71,
	})

	--==============================================
	-- OPEN / CLOSE / MINIMIZE
	--==============================================

	function F.setOpen(open)
		isOpen = open
		busy = busy + 1
		local id = busy
		if open then
			holder.Visible = true
			fitScale()
			win.GroupTransparency = 1
			win.Position = UDim2.fromOffset(-40, 0)
			tween(win, 0.4, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
			F.refreshAll()
		else
			local tw = tween(win, 0.3, { GroupTransparency = 1, Position = UDim2.fromOffset(-40, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tw.Completed:Connect(function()
				if busy == id and not isOpen then holder.Visible = false end
			end)
		end
	end

	local function setMinimized(m)
		minimized = m
		local h = m and HEAD or WH
		tween(holder, 0.3, { Size = UDim2.fromOffset(WW, h) }, Enum.EasingStyle.Quart)
		UI.miniBtn.Text = m and "+" or "-"
	end

	bind(UI.closeBtn.Activated, function() click() F.setOpen(false) end)
	bind(UI.miniBtn.Activated, function() click() setMinimized(not minimized) end)

	--==============================================
	-- DRAG (window, toggle, sliders)
	--==============================================

	local drag = nil

	local function makeDrag(object, handle, getScale, onTap)
		bind(handle.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				drag = { object = object, start = input.Position, pos = object.Position, scale = getScale, moved = false, onTap = onTap }
			end
		end)
	end

	bind(UIS.InputChanged, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if dragSlider then
			dragSlider.fromX(input.Position.X)
			return
		end
		local d = drag
		if d then
			local delta = input.Position - d.start
			if not d.moved and delta.Magnitude > 8 then d.moved = true end
			if d.moved then
				local sc = d.scale and d.scale() or 1
				d.object.Position = UDim2.new(d.pos.X.Scale, d.pos.X.Offset + delta.X / sc, d.pos.Y.Scale, d.pos.Y.Offset + delta.Y / sc)
			end
		end
		-- free camera look
		if S.free and (input.UserInputType == Enum.UserInputType.Touch or UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)) and not drag then
			fc.yaw = fc.yaw - input.Delta.X * 0.005
			fc.pitch = math.clamp(fc.pitch - input.Delta.Y * 0.005, -1.5, 1.5)
		end
	end)

	bind(UIS.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if dragSlider then
				dragSlider = nil
				list.ScrollingEnabled = true
				F.refreshAll()
			end
			local d = drag
			if d then
				drag = nil
				if not d.moved and d.onTap then d.onTap() end
			end
		end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.E then S.up = false end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.Q then S.down = false end
	end)

	bind(UIS.InputBegan, function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.RightControl then
			F.setOpen(not isOpen)
		end
		if S.fly or S.free then
			if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.E then S.up = true end
			if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.Q then S.down = true end
		end
	end)

	makeDrag(holder, header, function() return holderScale.Scale end)
	makeDrag(toggle, toggle, nil, function() click() F.setOpen(not isOpen) end)

	bind(UIS.JumpRequest, function()
		if S.infJump then
			local h = getHum()
			if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
		end
	end)

	pcall(function()
		local vu = game:GetService("VirtualUser")
		bind(player.Idled, function()
			if not Sh.antiAFK then return end
			vu:CaptureController()
			vu:ClickButton2(Vector2.new())
		end)
	end)

	--==============================================
	-- LOOPS (one Heartbeat, one Stepped, one RenderStep)
	--==============================================

	bind(RunService.Stepped, function() F.noclipStep() F.shieldStepped() end)

	bind(RunService.Heartbeat, function(dt)
		if not alive then return end

		-- fps
		fpsCount = fpsCount + 1
		fpsTimer = fpsTimer + dt
		if fpsTimer >= 0.5 then
			fpsValue = fpsCount / fpsTimer
			fpsCount, fpsTimer = 0, 0
		end

		F.applyHum()
		F.moveStep(dt)
		F.flyStep()
		F.shieldStep(dt)
		F.weatherKeep()

		-- spectate target gone
		if spectating and not (spectating.Parent and spectating.Character) then F.stopSpectate() end

		-- rgb theme
		if S.rgb and not S.perf then
			rgbTimer = rgbTimer + dt
			rgbHue = (rgbHue + dt * 0.12) % 1
			if rgbTimer > 0.08 then
				rgbTimer = 0
				Theme.A1 = Color3.fromHSV(rgbHue, 0.8, 1)
				Theme.A2 = Color3.fromHSV((rgbHue + 0.4) % 1, 0.85, 1)
				applyTheme()
			end
		end

		-- live labels
		liveTimer = liveTimer + dt
		if liveTimer >= 0.35 and isOpen and not minimized then
			liveTimer = 0
			for _, r in ipairs(rows) do
				if r.frame.Visible and (r.live or r.kind == "toggle" or r.kind == "slider" or r.id == "plist") then
					pcall(r.refresh)
				end
			end
			F.updateStatus()
		end

		-- marker distances
		if S.markers then
			local root = getRoot()
			if root then
				for _, m in ipairs(markerLabels) do
					m.t.Text = m.name .. "  " .. fmt0((root.Position - m.pos).Magnitude) .. "m"
				end
			end
		end

		pad.Visible = S.pad and (S.fly or S.free)
	end)

	local previewAngle = 0

	RunService:BindToRenderStep("AAYAN_ADMIN_CAM", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not alive then return end
		local c = cam()
		if not c then return end

		if S.free then
			F.freeStep(dt)
		elseif S.lock and lockCF then
			c.CFrame = lockCF
		else
			if S.fovOn and c.FieldOfView ~= S.fov then c.FieldOfView = S.fov end
			if S.smooth then
				smoothCF = smoothCF or c.CFrame
				smoothCF = smoothCF:Lerp(c.CFrame, 1 - math.exp(-dt * 14))
				c.CFrame = smoothCF
			end
		end

		F.weatherUpdate(dt, os.clock())

		-- navigation arrow
		local w = wps[S.selWp]
		local root = getRoot()
		if S.navigate and w and root then
			nav.Visible = true
			local look = c.CFrame.LookVector
			local d = w.cf.Position - root.Position
			local cross = look.X * d.Z - look.Z * d.X
			local dot = look.X * d.X + look.Z * d.Z
			navArrow.Rotation = math.deg(math.atan2(cross, dot))
			navText.Text = w.name .. "\n" .. fmt0(d.Magnitude) .. " studs"
		else
			nav.Visible = false
		end

		if not S.reduceAnim and not S.perf then
			winGrad.Rotation = (winGrad.Rotation + 60 * dt) % 360
			toggleGrad.Rotation = (toggleGrad.Rotation + 80 * dt) % 360
			titleGrad.Offset = Vector2.new(math.sin(os.clock() * 1.4) * 0.3, 0)
		end

		if previewModel and previewVp and isOpen and not minimized and curTab == "VISUAL" and not S.perf then
			previewAngle = previewAngle + dt * 1.2
			previewModel:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, previewAngle, 0))
		end
	end)

	--==============================================
	-- RESPAWN
	--==============================================

	local function onCharacter(char)
		task.wait(0.6)
		if not alive then return end
		respawns = respawns + 1
		origCollide, walkApplied, jumpApplied = {}, false, false
		flyBV, flyBG = nil, nil
		F.captureDefaults()
		S.up, S.down = false, false
		F.rebuildFx()
		F.refreshPreview()
		F.applyHum()
		F.shieldReset()
		F.weatherReapply()
		notify("Respawn detected", "Movement controls re-initialised", "on")
	end

	bind(player.CharacterAdded, onCharacter)

	--==============================================
	-- SHUTDOWN
	--==============================================

	local function shutdown()
		if not alive then return end
		alive = false
		pcall(function() RunService:UnbindFromRenderStep("AAYAN_ADMIN_CAM") end)
		pcall(F.stopFly)
		pcall(F.restoreCollision)
		pcall(F.restoreLook)
		pcall(F.destroyFx)
		pcall(F.shieldShutdown)
		pcall(F.weatherStop)
		pcall(function()
			if S.free or S.lock then
				cam().CameraType = Enum.CameraType.Custom
				local h = getHum()
				if h then cam().CameraSubject = h end
			end
			local h = getHum()
			if h then
				h.PlatformStand = false
				if walkApplied then h.WalkSpeed = Def.walk end
				if jumpApplied then h.JumpPower = Def.jump h.UseJumpPower = Def.useJP end
			end
		end)
		if markerFolder then markerFolder:Destroy() end
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		conns = {}
		if sg then sg:Destroy() end
		_G.AAYAN_ADMIN_SHUTDOWN = nil
	end

	_G.AAYAN_ADMIN_SHUTDOWN = shutdown

	--==============================================
	-- START
	--==============================================

	pcall(function() Def.sens = UserSettings():GetService("UserGameSettings").MouseSensitivity S.sens = Def.sens end)
	F.captureDefaults()

	do
		local r = getRoot()
		spawnCF = r and r.CFrame or nil
	end

	applyQuickPlacement()
	F.setTab("MOVE")
	F.refreshPreview()
	fitScale()
	if workspace.CurrentCamera then
		bind(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), fitScale)
	end

	F.setOpen(true)
	banner()
	notify("AAYAN ADMIN V3 Loaded Successfully!", "Tap the toggle on the left to hide / show", "on")
end

Boot()

print("====================================")
print("        AAYAN ADMIN V3 LOADED")
print("====================================")
