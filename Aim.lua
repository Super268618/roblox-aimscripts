local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

--------------------------------------------------------------------------------
-- CONFIGURATION & SETTINGS STATE
--------------------------------------------------------------------------------
local SETTINGS = {
	TOGGLE_KEY = Enum.KeyCode.F,
	SWITCH_LEFT_KEY = Enum.KeyCode.Q,
	SWITCH_RIGHT_KEY = Enum.KeyCode.E,
	
	BASE_MAX_RADIUS = 200,
	SNIPER_MAX_RADIUS = 500,
	
	WEIGHT_SCREEN_CENTER = 0.6,
	WEIGHT_WORLD_DISTANCE = 0.4,
	
	BASE_CAMERA_OFFSET = Vector3.new(2.2, 1.8, 7.5),
	
	SMOOTHING_FACTOR = 0.25,
	PREDICTION_MULT = 0.09,
	RAY_THICKNESS = 0.6,
	
	BODYGYRO_P = 60000,
	BODYGYRO_D = 600,
	WALL_COLLISION_RADIUS = 0.4,
	
	TargetPartSelection = "Head", 
	SmoothingSpeed = 0.25,
	PredictionScale = 0.09,
}

--------------------------------------------------------------------------------
-- STATE VARIABLES
--------------------------------------------------------------------------------
local isLocked = false
local currentTarget = nil
local hudContainer = nil
local bodyGyro = nil

local lastTargetPosition = nil
local velocityEstimate = Vector3.zero
local smoothedTargetCFrame = nil
local currentCameraOffset = SETTINGS.BASE_CAMERA_OFFSET

--------------------------------------------------------------------------------
-- UI SYSTEM & SETTINGS MENU SETUP
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
settingsMenu.Size = UDim2.new(0, 260, 0, 280)
settingsMenu.AnchorPoint = Vector2.new(1, 0)
settingsMenu.Position = UDim2.new(1, -20, 0, 65)
settingsMenu.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
settingsMenu.Visible = false
settingsMenu.Parent = screenGui

local menuCorner = Instance.new("UICorner")
menuCorner.CornerRadius = UDim.new(0, 8)
menuCorner.Parent = settingsMenu

local menuTitle = Instance.new("TextLabel")
menuTitle.Size = UDim2.new(1, 0, 0, 40)
menuTitle.BackgroundTransparency = 1
menuTitle.Text = "LOCK SETTINGS"
menuTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
menuTitle.Font = Enum.Font.SourceSansBold
menuTitle.TextSize = 16
menuTitle.Parent = settingsMenu

local function createDropdownButton(name, yPos, selectionValue)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0.9, 0, 0, 35)
	btn.Position = UDim2.new(0.05, 0, 0, yPos)
	btn.BackgroundColor3 = SETTINGS.TargetPartSelection == selectionValue and Color3.fromRGB(70, 130, 180) or Color3.fromRGB(40, 40, 40)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = name
	btn.Font = Enum.Font.SourceSans
	btn.TextSize = 14
	btn.Parent = settingsMenu
	
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = btn
	return btn
end

local btnHead = createDropdownButton("Target: Head", 45, "Head")
local btnTorso = createDropdownButton("Target: UpperTorso", 85, "UpperTorso")
local btnLegs = createDropdownButton("Target: Legs", 125, "Legs")
local btnAuto = createDropdownButton("Target: Auto (Dynamic)", 165, "Auto")

-- Auto Feature Toggle Button
local autoFeatureBtn = Instance.new("TextButton")
autoFeatureBtn.Size = UDim2.new(0.9, 0, 0, 35)
autoFeatureBtn.Position = UDim2.new(0.05, 0, 0, 215)
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

local function updateSelectionVisuals(selected)
	SETTINGS.TargetPartSelection = selected
	btnHead.BackgroundColor3 = (selected == "Head") and Color3.fromRGB(70, 130, 180) or Color3.fromRGB(40, 40, 40)
	btnTorso.BackgroundColor3 = (selected == "UpperTorso") and Color3.fromRGB(70, 130, 180) or Color3.fromRGB(40, 40, 40)
	btnLegs.BackgroundColor3 = (selected == "Legs") and Color3.fromRGB(70, 130, 180) or Color3.fromRGB(40, 40, 40)
	btnAuto.BackgroundColor3 = (selected == "Auto") and Color3.fromRGB(70, 130, 180) or Color3.fromRGB(40, 40, 40)
end

btnHead.Activated:Connect(function() updateSelectionVisuals("Head") end)
btnTorso.Activated:Connect(function() updateSelectionVisuals("UpperTorso") end)
btnLegs.Activated:Connect(function() updateSelectionVisuals("Legs") end)
btnAuto.Activated:Connect(function() updateSelectionVisuals("Auto") end)

autoFeatureBtn.Activated:Connect(function()
	isAutoFeatureActive = not isAutoFeatureActive
	autoFeatureBtn.Text = isAutoFeatureActive and "Auto Feature: ON" or "Auto Feature: OFF"
	autoFeatureBtn.BackgroundColor3 = isAutoFeatureActive and Color3.fromRGB(50, 180, 80) or Color3.fromRGB(180, 50, 50)
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
	if now - lastCacheUpdate > 0.5 then
		lastCacheUpdate = now
		table.clear(cachedModels)
		for _, obj in ipairs(workspace:GetChildren()) do
			if obj:IsA("Model") and obj ~= player.Character then
				local hum = obj:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					local head = obj:FindFirstChild("Head")
					local torso = obj:FindFirstChild("UpperTorso") or obj:FindFirstChild("Torso") or obj:FindFirstChild("HumanoidRootPart")
					if head or torso then
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
			if name:find("sniper") or name:find("awp") or name:find("rifle") or name:find("scope") or name:find("barrett") then
				return SETTINGS.SNIPER_MAX_RADIUS
			end
		end
	end

	return SETTINGS.BASE_MAX_RADIUS
end

--------------------------------------------------------------------------------
-- FULLY AUTOMATED & ROBUST MULTI-PART SELECTION DISCOVERY
--------------------------------------------------------------------------------
local function getTargetPart(model)
	if not model then return nil end

	if isAutoFeatureActive and SETTINGS.TargetPartSelection == "Auto" then
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then return head end
		local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then return torso end
	end

	if SETTINGS.TargetPartSelection == "Head" then
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then return head end
	end

	if SETTINGS.TargetPartSelection == "UpperTorso" then
		local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
		if torso and torso:IsA("BasePart") then return torso end
	end

	if SETTINGS.TargetPartSelection == "Legs" then
		for _, partName in ipairs({"RightLeg", "LeftLeg", "RightLowerLeg", "LeftLowerLeg", "RightUpperLeg", "LeftUpperLeg"}) do
			local legPart = model:FindFirstChild(partName)
			if legPart and legPart:IsA("BasePart") then
				return legPart
			end
		end
	end

	return model:FindFirstChild("Head") or model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
end

--------------------------------------------------------------------------------
-- VELOCITY & PREDICTION MATH
--------------------------------------------------------------------------------
local function calculateDynamicTargetPosition(targetPart, dt)
	if not targetPart then return nil end

	local currentPos = targetPart.Position

	if lastTargetPosition then
		local rawVel = (currentPos - lastTargetPosition) / math.max(dt, 0.001)
		velocityEstimate = velocityEstimate:Lerp(rawVel, 0.3)
	else
		velocityEstimate = Vector3.zero
	end
	lastTargetPosition = currentPos

	local predictedPos = currentPos + (velocityEstimate * SETTINGS.PredictionScale)

	if not smoothedTargetCFrame then
		smoothedTargetCFrame = CFrame.new(predictedPos)
	else
		smoothedTargetCFrame = smoothedTargetCFrame:Lerp(CFrame.new(predictedPos), SETTINGS.SmoothingSpeed)
	end

	return smoothedTargetCFrame.Position
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
-- PHYSICS BODYGYRO SETUP
--------------------------------------------------------------------------------
local function setupBodyGyro(character)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not root then return end

	local oldGyro = root:FindFirstChild("CameraLockBodyGyro")
	if oldGyro then oldGyro:Destroy() end

	bodyGyro = Instance.new("BodyGyro")
	bodyGyro.Name = "CameraLockBodyGyro"
	bodyGyro.P = SETTINGS.BODYGYRO_P
	bodyGyro.D = SETTINGS.BODYGYRO_D
	bodyGyro.MaxTorque = Vector3.new(0, 0, 0)
	bodyGyro.CFrame = root.CFrame
	bodyGyro.Parent = root
end

local function setPhysicsEnabled(enable)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	
	if hum then hum.AutoRotate = not enable end

	if bodyGyro then
		bodyGyro.MaxTorque = enable and Vector3.new(0, math.huge, 0) or Vector3.zero
	end
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
-- PROCEDURAL 3D DYNAMIC CAMERA OFFSET ENGINE LOOP
--------------------------------------------------------------------------------
local function updateCamera(dt)
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

	if bodyGyro then
		bodyGyro.CFrame = CFrame.lookAt(playerRoot.Position, Vector3.new(aimTargetPos.X, playerRoot.Position.Y, aimTargetPos.Z))
	end

	local deltaToTarget = aimTargetPos - playerRoot.Position
	local flatDist = Vector3.new(deltaToTarget.X, 0, deltaToTarget.Z).Magnitude
	local heightDiff = deltaToTarget.Y

	local targetForwardDepth = math.clamp(flatDist * 0.25, 4.0, 14.0)
	local targetVerticalHeight = math.clamp(1.6 + (heightDiff * 0.05), 0.8, 4.0)
	local targetSideWidth = math.clamp(2.2 - (flatDist * 0.002), 1.2, 2.8)

	local proceduralCameraOffset = Vector3.new(targetSideWidth, targetVerticalHeight, targetForwardDepth)
	
	currentCameraOffset = currentCameraOffset:Lerp(proceduralCameraOffset, math.clamp(dt * 8, 0.05, 0.3))

	local shoulderCFrame = playerRoot.CFrame * CFrame.new(currentCameraOffset)
	local idealCamPos = shoulderCFrame.Position
	local playerCenterPos = playerRoot.Position + Vector3.new(0, 1.5, 0)

	local camRayParams = RaycastParams.new()
	camRayParams.FilterType = Enum.RaycastFilterType.Exclude
	camRayParams.FilterDescendantsInstances = {character, currentTarget.Parent}

	local camHit = workspace:Spherecast(playerCenterPos, SETTINGS.RAY_THICKNESS, idealCamPos - playerCenterPos, camRayParams)
	local finalCamPos = camHit and (camHit.Position + (camHit.Normal * SETTINGS.WALL_COLLISION_RADIUS)) or idealCamPos

	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	camera.CFrame = CFrame.lookAt(finalCamPos, aimTargetPos)
end

--------------------------------------------------------------------------------
-- CONTROLLER METHODS
--------------------------------------------------------------------------------
function unlockCamera()
	if not isLocked and not currentTarget then return end
	isLocked = false
	currentTarget = nil
	lastTargetPosition = nil
	smoothedTargetCFrame = nil
	currentCameraOffset = SETTINGS.BASE_CAMERA_OFFSET

	RunService:UnbindFromRenderStep("UniversalLockOverride")
	setPhysicsEnabled(false)

	if hudContainer then 
		hudContainer:Destroy() 
		hudContainer = nil
	end

	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default

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

			setupBodyGyro(character)
			setPhysicsEnabled(true)

			isLocked = true
			currentTarget = target
			createHUD(target)

			updateUIButton(true)

			RunService:BindToRenderStep("UniversalLockOverride", Enum.RenderPriority.Camera.Value + 10, updateCamera)
		end
	end
end

--------------------------------------------------------------------------------
-- BINDINGS
--------------------------------------------------------------------------------
player.CharacterAdded:Connect(function(char)
	unlockCamera()
	setupBodyGyro(char)
end)

if player.Character then
	setupBodyGyro(player.Character)
end

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
