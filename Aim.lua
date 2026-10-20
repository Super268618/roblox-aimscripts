local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

--------------------------------------------------------------------------------
-- CONFIGURATION & SETTINGS STATE (DISTANCE-SCALED SNAPPY AIM)
--------------------------------------------------------------------------------
local SETTINGS = {
	TOGGLE_KEY = Enum.KeyCode.F,
	SWITCH_LEFT_KEY = Enum.KeyCode.Q,
	SWITCH_RIGHT_KEY = Enum.KeyCode.E,
	
	BASE_MAX_RADIUS = 250,
	SNIPER_MAX_RADIUS = 350,
	
	WEIGHT_SCREEN_CENTER = 0.5,
	WEIGHT_WORLD_DISTANCE = 0.5,
	
	-- Distance-scaled snap response rates
	MIN_SNAP_SPEED = 15,
	MAX_SNAP_SPEED = 60,
	CLOSE_DISTANCE = 15,
	FAR_DISTANCE = 120,
	
	PREDICTION_SCALE = 0.015,
}

--------------------------------------------------------------------------------
-- STATE VARIABLES
--------------------------------------------------------------------------------
local isLocked = false
local currentTarget = nil
local hudContainer = nil

local lastTargetPosition = nil
local velocityEstimate = Vector3.zero
local isPredictionActive = true

--------------------------------------------------------------------------------
-- UI SYSTEM & STREAMLINED SETTINGS MENU
--------------------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
local existingGui = playerGui:FindFirstChild("CameraLockGui")
if existingGui then existingGui:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CameraLockGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Main Lock Button (Bottom Right)
local lockButton = Instance.new("TextButton")
lockButton.Name = "LockButton"
lockButton.Size = UDim2.new(0, 130, 0, 45)
lockButton.AnchorPoint = Vector2.new(1, 0.5)
lockButton.Position = UDim2.new(1, -20, 0.5, 0)
lockButton.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
lockButton.TextColor3 = Color3.fromRGB(255, 255, 255)
lockButton.Text = "LOCK: OFF"
lockButton.Font = Enum.Font.SourceSansBold
lockButton.TextSize = 18
lockButton.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = lockButton

-- Settings Cog Button (Top Right)
local settingsBtn = Instance.new("TextButton")
settingsBtn.Name = "SettingsButton"
settingsBtn.Size = UDim2.new(0, 35, 0, 35)
settingsBtn.AnchorPoint = Vector2.new(1, 0)
settingsBtn.Position = UDim2.new(1, -20, 0, 20)
settingsBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
settingsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
settingsBtn.Text = "⚙"
settingsBtn.Font = Enum.Font.SourceSansBold
settingsBtn.TextSize = 20
settingsBtn.Parent = screenGui

local settingsCorner = Instance.new("UICorner")
settingsCorner.CornerRadius = UDim.new(0, 6)
settingsCorner.Parent = settingsBtn

-- Settings Menu Frame
local settingsMenu = Instance.new("Frame")
settingsMenu.Name = "SettingsMenu"
settingsMenu.Size = UDim2.new(0, 220, 0, 135)
settingsMenu.AnchorPoint = Vector2.new(1, 0)
settingsMenu.Position = UDim2.new(1, -20, 0, 65)
settingsMenu.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
settingsMenu.Visible = false
settingsMenu.Parent = screenGui

local menuCorner = Instance.new("UICorner")
menuCorner.CornerRadius = UDim.new(0, 8)
menuCorner.Parent = settingsMenu

local menuTitle = Instance.new("TextLabel")
menuTitle.Size = UDim2.new(1, 0, 0, 35)
menuTitle.BackgroundTransparency = 1
menuTitle.Text = "LOCK SETTINGS"
menuTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
menuTitle.Font = Enum.Font.SourceSansBold
menuTitle.TextSize = 15
menuTitle.Parent = settingsMenu

-- Auto Feature Toggle Button
local autoFeatureBtn = Instance.new("TextButton")
autoFeatureBtn.Size = UDim2.new(0.9, 0, 0, 35)
autoFeatureBtn.Position = UDim2.new(0.05, 0, 0, 40)
autoFeatureBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
autoFeatureBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoFeatureBtn.Text = "Auto Feature: ON"
autoFeatureBtn.Font = Enum.Font.SourceSansBold
autoFeatureBtn.TextSize = 14
autoFeatureBtn.Parent = settingsMenu

local autoCorner = Instance.new("UICorner")
autoCorner.CornerRadius = UDim.new(0, 6)
autoCorner.Parent = autoFeatureBtn

local isAutoFeatureActive = true

autoFeatureBtn.Activated:Connect(function()
	isAutoFeatureActive = not isAutoFeatureActive
	autoFeatureBtn.Text = isAutoFeatureActive and "Auto Feature: ON" or "Auto Feature: OFF"
	autoFeatureBtn.BackgroundColor3 = isAutoFeatureActive and Color3.fromRGB(50, 180, 80) or Color3.fromRGB(180, 50, 50)
end)

-- Velocity Prediction Toggle Button
local predictionBtn = Instance.new("TextButton")
predictionBtn.Size = UDim2.new(0.9, 0, 0, 35)
predictionBtn.Position = UDim2.new(0.05, 0, 0, 85)
predictionBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
predictionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
predictionBtn.Text = "Prediction: ON"
predictionBtn.Font = Enum.Font.SourceSansBold
predictionBtn.TextSize = 14
predictionBtn.Parent = settingsMenu

local predictionCorner = Instance.new("UICorner")
predictionCorner.CornerRadius = UDim.new(0, 6)
predictionCorner.Parent = predictionBtn

predictionBtn.Activated:Connect(function()
	isPredictionActive = not isPredictionActive
	predictionBtn.Text = isPredictionActive and "Prediction: ON" or "Prediction: OFF"
	predictionBtn.BackgroundColor3 = isPredictionActive and Color3.fromRGB(50, 180, 80) or Color3.fromRGB(180, 50, 50)
end)

settingsBtn.Activated:Connect(function()
	settingsMenu.Visible = not settingsMenu.Visible
end)

local function updateUIButton(active)
	if lockButton then
		lockButton.Text = active and "LOCK: ON" or "LOCK: OFF"
		lockButton.BackgroundColor3 = active and Color3.fromRGB(220, 50, 50) or Color3.fromRGB(35, 35, 35)
	end
end

--------------------------------------------------------------------------------
-- HIGH-PERFORMANCE CACHED WORKSPACE MODEL SCANNER
--------------------------------------------------------------------------------
local cachedModels = {}
local lastCacheUpdate = 0

RunService.Heartbeat:Connect(function()
	local now = tick()
	if now - lastCacheUpdate > 0.4 then
		lastCacheUpdate = now
		table.clear(cachedModels)
		for _, obj in ipairs(workspace:GetChildren()) do
			if obj:IsA("Model") and obj ~= player.Character then
				local hum = obj:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					local torso = obj:FindFirstChild("UpperTorso") or obj:FindFirstChild("Torso") or obj:FindFirstChild("HumanoidRootPart")
					if torso then
						table.insert(cachedModels, {Model = obj, Humanoid = hum})
					end
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- UNIVERSAL RANGE SCALING
--------------------------------------------------------------------------------
local function getMaxRadius()
	local char = player.Character
	if not char then return SETTINGS.BASE_MAX_RADIUS end

	for _, item in ipairs(char:GetChildren()) do
		if item:IsA("Tool") then
			local name = item.Name:lower()
			if name:find("gun") or name:find("revolver") or name:find("sheriff") then
				return SETTINGS.SNIPER_MAX_RADIUS
			end
		end
	end

	return SETTINGS.BASE_MAX_RADIUS
end

--------------------------------------------------------------------------------
-- TORSO-ONLY TARGET PART DISCOVERY
--------------------------------------------------------------------------------
local function getTargetPart(model)
	if not model then return nil end

	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
	if torso and torso:IsA("BasePart") then
		return torso
	end

	return model:FindFirstChild("HumanoidRootPart")
end

--------------------------------------------------------------------------------
-- TOGGLEABLE VELOCITY PREDICTION & PRECISE MATH
--------------------------------------------------------------------------------
local function calculateDynamicTargetPosition(targetPart, dt)
	if not targetPart then return nil end

	local currentPos = targetPart.Position

	if lastTargetPosition then
		local rawVel = (currentPos - lastTargetPosition) / math.max(dt, 0.001)
		velocityEstimate = velocityEstimate:Lerp(rawVel, 0.25)
	else
		velocityEstimate = Vector3.zero
	end
	lastTargetPosition = currentPos

	local predictedPos = currentPos
	if isPredictionActive then
		predictedPos = currentPos + (velocityEstimate * SETTINGS.PREDICTION_SCALE)
	end

	return predictedPos
end

--------------------------------------------------------------------------------
-- TARGET EVALUATION
--------------------------------------------------------------------------------
local function evaluateTarget(entry, playerRoot)
	local model = entry.Model
	local targetPart = getTargetPart(model)
	if not targetPart then return nil, math.huge end

	local maxDist = getMaxRadius()
	local deltaWorld = targetPart.Position - playerRoot.Position
	local flatWorldDist = Vector3.new(deltaWorld.X, 0, deltaWorld.Z).Magnitude
	
	if flatWorldDist > maxDist then 
		return nil, math.huge 
	end

	local screenPos, onScreen = camera:WorldToViewportPoint(targetPart.Position)
	if not onScreen or screenPos.Z <= 0 then 
		return nil, math.huge 
	end

	local vpSize = camera.ViewportSize
	local vpCenter = Vector2.new(vpSize.X * 0.5, vpSize.Y * 0.5)
	local targetScreenVec = Vector2.new(screenPos.X, screenPos.Y)
	
	local maxScreenRadius = vpCenter.Magnitude
	local screenDist = (targetScreenVec - vpCenter).Magnitude

	local normalizedScreen = math.clamp(screenDist / maxScreenRadius, 0, 1)
	local normalizedWorld = math.clamp(flatWorldDist / maxDist, 0, 1)

	local compositeScore = (normalizedScreen * SETTINGS.WEIGHT_SCREEN_CENTER) + (normalizedWorld * SETTINGS.WEIGHT_WORLD_DISTANCE)
	return targetPart, compositeScore
end

local function getBestTarget()
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return nil end
	local playerRoot = character.HumanoidRootPart

	local bestTarget = nil
	local lowestScore = math.huge

	for _, entry in ipairs(cachedModels) do
		local targetPart, score = evaluateTarget(entry, playerRoot)
		if targetPart and score < lowestScore then
			lowestScore = score
			bestTarget = targetPart
		end
	end

	return bestTarget
end

--------------------------------------------------------------------------------
-- HUD SETUP
--------------------------------------------------------------------------------
local function createHUD(targetPart)
	if hudContainer then hudContainer:Destroy() end
	if not targetPart then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "LockTargetHUD"
	bb.Size = UDim2.new(0, 45, 0, 45)
	bb.AlwaysOnTop = true
	bb.Adornee = targetPart

	local box = Instance.new("Frame")
	box.Size = UDim2.new(1, 0, 1, 0)
	box.BackgroundTransparency = 1
	box.Parent = bb

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 50, 50)
	stroke.Thickness = 2.5
	stroke.Parent = box

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(1, 0)
	boxCorner.Parent = box

	bb.Parent = targetPart
	hudContainer = bb
end

--------------------------------------------------------------------------------
-- DISTANCE-SCALED SNAPPY AIM ENGINE (ROBLOX NATIVE CAMERA BINDING)
--------------------------------------------------------------------------------
local function updateDistanceScaledAim(dt)
	local character = player.Character
	if not isLocked or not currentTarget or not currentTarget.Parent or not character then
		unlockCamera()
		return
	end

	local playerRoot = character:FindFirstChild("HumanoidRootPart")
	local playerHum = character:FindFirstChildOfClass("Humanoid")
	if not playerRoot or not playerHum or (playerHum.Health and playerHum.Health <= 0) then
		unlockCamera()
		return
	end

	local aimTargetPos = calculateDynamicTargetPosition(currentTarget, dt)

	-- Dynamically scale snap speed based on distance (snappy when close, smooth when far)
	local distance = (currentTarget.Position - playerRoot.Position).Magnitude
	local alpha = math.clamp((distance - SETTINGS.CLOSE_DISTANCE) / (SETTINGS.FAR_DISTANCE - SETTINGS.CLOSE_DISTANCE), 0, 1)
	local currentSnapSpeed = SETTINGS.MAX_SNAP_SPEED + (SETTINGS.MIN_SNAP_SPEED - SETTINGS.MAX_SNAP_SPEED) * alpha

	local currentCamCFrame = camera.CFrame
	local targetLookCFrame = CFrame.lookAt(currentCamCFrame.Position, aimTargetPos)
	
	camera.CFrame = currentCamCFrame:Lerp(targetLookCFrame, math.clamp(dt * currentSnapSpeed, 0.2, 1.0))
end

--------------------------------------------------------------------------------
-- CONTROLLER METHODS
--------------------------------------------------------------------------------
function unlockCamera()
	if not isLocked and not currentTarget then return end
	isLocked = false
	currentTarget = nil
	lastTargetPosition = nil

	RunService:UnbindFromRenderStep("UniversalLockOverride")

	if hudContainer then 
		hudContainer:Destroy() 
		hudContainer = nil
	end

	updateUIButton(false)
end

local function toggleLock()
	if isLocked then
		unlockCamera()
	else
		local target = getBestTarget()
		if target then
			local character = player.Character
			if not character then return end

			isLocked = true
			currentTarget = target
			createHUD(target)

			updateUIButton(true)

			RunService:BindToRenderStep("UniversalLockOverride", Enum.RenderPriority.Camera.Value + 10, updateDistanceScaledAim)
		end
	end
end

--------------------------------------------------------------------------------
-- BINDINGS
--------------------------------------------------------------------------------
player.CharacterAdded:Connect(function(char)
	unlockCamera()
end)

lockButton.Activated:Connect(toggleLock)

ContextActionService:BindAction("ToggleLockAction", function(_, state)
	if state == Enum.UserInputState.Begin then toggleLock() end
end, false, SETTINGS.TOGGLE_KEY)

ContextActionService:BindAction("SwitchTargetLeft", function(_, state)
	if state == Enum.UserInputState.Begin then
		if not isLocked then return end
		local target = getBestTarget()
		if target then
			currentTarget = target
			createHUD(target)
		end
	end
end, false, SETTINGS.SWITCH_LEFT_KEY)
