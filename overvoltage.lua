
--!optimize 2
local Decimals = 4
local Clock = os.clock()

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

if not player then Players.PlayerAdded:Wait(); player = Players.LocalPlayer end
if not Camera then repeat task.wait() until Workspace.CurrentCamera; Camera = Workspace.CurrentCamera end
if not player or not Camera then warn("Combined ESP: Failed to get Player or Camera."); return end

local espSettings = {
    -- Box ESP Settings
    BoxEnabled = false,
    BoxColor = Color3.fromRGB(168, 255, 0),
    OutlineColor = Color3.fromRGB(0, 0, 0),
    BoxThickness = 2,
    BoxTransparency = 0.2,
    MinimumDistance = 5,
    BoxStyle = "Classic",
    CornerSize = 5,

    -- Combined ESP Settings (Dual Highlight + Hiding)
    CombinedESPEnabled = false,
    HeadHighlightEnabled = false,
    HeadHighlightColor = Color3.fromRGB(0, 255, 0),
    HeadFillTransparency = 0,
    HeadHighlightDepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    BodyHighlightEnabled = false,
    BodyHighlightColor = Color3.fromRGB(255, 0, 0),
    BodyFillTransparency = 0,
    BodyHighlightDepthMode = Enum.HighlightDepthMode.AlwaysOnTop,

    -- Removals (now separate)
    Removals = {},

    -- Target Settings
    TargetParentModelName = "Male",
    TargetHeadPartName = "Head",

    -- Distance ESP
    DistanceESPEnabled = false,
    DistanceESPSize = 32,
    DistanceESPColor = Color3.fromRGB(255, 255, 255),

    -- Fade on Death
    FadeOnDeath = true,
    FadeDuration = 0.5
}

local function isRemovalEnabled(removalName)
    for _, v in ipairs(espSettings.Removals) do
        if v == removalName then return true end
    end
    return false
end

local function isAlive(model)
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BallSocketConstraint") then
            return false
        end
    end
    return true
end

-- Centralized Drawing Resource Manager
local DrawingManager = {
    objects = {},
    add = function(self, obj)
        table.insert(self.objects, obj)
        return obj
    end,
    cleanup = function(self)
        for _, obj in ipairs(self.objects) do
            if obj.Remove then pcall(function() obj:Remove() end) end
        end
        self.objects = {}
    end
}

-- ESPBoxManager module
local ESPBoxManager = {}
function ESPBoxManager.new()
    local self = { boxes = {} }

    local lineNames = {"TopLine", "LeftLine", "RightLine", "BottomLine",
        "TopLeftCorner1", "TopLeftCorner2", "TopRightCorner1", "TopRightCorner2",
        "BottomLeftCorner1", "BottomLeftCorner2", "BottomRightCorner1", "BottomRightCorner2"}

    function self:createBox(model)
        local espBox = { Model = model }
        espBox.Lines = {}
        for _, name in ipairs(lineNames) do
            local line = DrawingManager:add(Drawing.new("Line"))
            line.Thickness = espSettings.BoxThickness
            line.Color = espSettings.BoxColor
            line.Transparency = espSettings.BoxTransparency
            line.Visible = false
            espBox.Lines[name] = line
        end
        table.insert(self.boxes, espBox)
        return espBox
    end

    function self:cleanupBox(espBox)
        for _, line in pairs(espBox.Lines) do
            if line.Remove then pcall(function() line:Remove() end) end
        end
    end

    function self:updateBoxes(cachedWorkspaceChildren, cachedDescendantsMap)
        local currentBoxes = {}
        for i = #self.boxes, 1, -1 do
            local espBox = self.boxes[i]
            local isValid = pcall(self.updateBox, self, espBox, cachedDescendantsMap and cachedDescendantsMap[espBox.Model] or nil)
            if not isValid or not espBox.Model or not espBox.Model.Parent then
                self:cleanupBox(espBox)
                table.remove(self.boxes, i)
            else
                currentBoxes[espBox.Model] = true
            end
        end
        if espSettings.BoxEnabled then
            for _, object in ipairs(cachedWorkspaceChildren) do
                if object:IsA("Model") and object.Name == espSettings.TargetParentModelName and not currentBoxes[object] then
                    self:createBox(object)
                end
            end
        end
    end

    function self:updateBox(espBox, cachedDescendants)
        local model = espBox.Model
        if not model or not model.Parent or not isAlive(model) then
            self:cleanupBox(espBox)
            return false
        end

        if not espSettings.BoxEnabled then
            for _, line in pairs(espBox.Lines) do line.Visible = false end
            return true
        end

        local modelDescendants = cachedDescendants or model:GetDescendants()
        local parts = {}
        for _, part in ipairs(modelDescendants) do if part:IsA("BasePart") then table.insert(parts, part) end end
        if #parts == 0 then
            for _, line in pairs(espBox.Lines) do line.Visible = false end
            return true
        end

        local primaryPart = model.PrimaryPart or parts[1]
        local distance = (Camera.CFrame.Position - primaryPart.Position).Magnitude
        if distance < espSettings.MinimumDistance then
            for _, line in pairs(espBox.Lines) do line.Visible = false end
            return true
        end

        local minX, minY = math.huge, math.huge
        local maxX, maxY = -math.huge, -math.huge
        local isOnScreen = false

        for _, part in ipairs(parts) do
            local partCorners = {
                part.CFrame * Vector3.new(-part.Size.X/2, -part.Size.Y/2, -part.Size.Z/2), part.CFrame * Vector3.new(-part.Size.X/2, -part.Size.Y/2, part.Size.Z/2),
                part.CFrame * Vector3.new(-part.Size.X/2, part.Size.Y/2, -part.Size.Z/2), part.CFrame * Vector3.new(-part.Size.X/2, part.Size.Y/2, part.Size.Z/2),
                part.CFrame * Vector3.new(part.Size.X/2, -part.Size.Y/2, -part.Size.Z/2), part.CFrame * Vector3.new(part.Size.X/2, -part.Size.Y/2, part.Size.Z/2),
                part.CFrame * Vector3.new(part.Size.X/2, part.Size.Y/2, -part.Size.Z/2), part.CFrame * Vector3.new(part.Size.X/2, part.Size.Y/2, part.Size.Z/2)
            }
            for _, cornerPos in ipairs(partCorners) do
                local screenPoint, onScreen = Camera:WorldToViewportPoint(cornerPos)
                if onScreen then
                    isOnScreen = true
                    minX = math.min(minX, screenPoint.X); minY = math.min(minY, screenPoint.Y)
                    maxX = math.max(maxX, screenPoint.X); maxY = math.max(maxY, screenPoint.Y)
                end
            end
        end

        for _, line in pairs(espBox.Lines) do
            line.Thickness = espSettings.BoxThickness
            line.Color = espSettings.BoxColor
            line.Transparency = espSettings.BoxTransparency
            line.Visible = false
        end

        local boxStyle = espSettings.BoxStyle
        if boxStyle == "Full" then boxStyle = "Classic" end
        if boxStyle == "Corner" then boxStyle = "Corners" end

        if isOnScreen then
            if boxStyle == "Classic" then
                local linesToDraw = {espBox.Lines.TopLine, espBox.Lines.LeftLine, espBox.Lines.RightLine, espBox.Lines.BottomLine}
                espBox.Lines.TopLine.From = Vector2.new(minX, minY); espBox.Lines.TopLine.To = Vector2.new(maxX, minY)
                espBox.Lines.LeftLine.From = Vector2.new(minX, minY); espBox.Lines.LeftLine.To = Vector2.new(minX, maxY)
                espBox.Lines.RightLine.From = Vector2.new(maxX, minY); espBox.Lines.RightLine.To = Vector2.new(maxX, maxY)
                espBox.Lines.BottomLine.From = Vector2.new(minX, maxY); espBox.Lines.BottomLine.To = Vector2.new(maxX, maxY)
                for _, line in ipairs(linesToDraw) do line.Visible = true end
            else
                local cornerSize = espSettings.CornerSize
                local cornersToDraw = {espBox.Lines.TopLeftCorner1, espBox.Lines.TopLeftCorner2, espBox.Lines.TopRightCorner1, espBox.Lines.TopRightCorner2,
                    espBox.Lines.BottomLeftCorner1, espBox.Lines.BottomLeftCorner2, espBox.Lines.BottomRightCorner1, espBox.Lines.BottomRightCorner2}
                espBox.Lines.TopLeftCorner1.From = Vector2.new(minX, minY); espBox.Lines.TopLeftCorner1.To = Vector2.new(minX + cornerSize, minY)
                espBox.Lines.TopLeftCorner2.From = Vector2.new(minX, minY); espBox.Lines.TopLeftCorner2.To = Vector2.new(minX, minY + cornerSize)
                espBox.Lines.TopRightCorner1.From = Vector2.new(maxX, minY); espBox.Lines.TopRightCorner1.To = Vector2.new(maxX - cornerSize, minY)
                espBox.Lines.TopRightCorner2.From = Vector2.new(maxX, minY); espBox.Lines.TopRightCorner2.To = Vector2.new(maxX, minY + cornerSize)
                espBox.Lines.BottomLeftCorner1.From = Vector2.new(minX, maxY); espBox.Lines.BottomLeftCorner1.To = Vector2.new(minX + cornerSize, maxY)
                espBox.Lines.BottomLeftCorner2.From = Vector2.new(minX, maxY); espBox.Lines.BottomLeftCorner2.To = Vector2.new(minX, maxY - cornerSize)
                espBox.Lines.BottomRightCorner1.From = Vector2.new(maxX, maxY); espBox.Lines.BottomRightCorner1.To = Vector2.new(maxX - cornerSize, maxY)
                espBox.Lines.BottomRightCorner2.From = Vector2.new(maxX, maxY); espBox.Lines.BottomRightCorner2.To = Vector2.new(maxX, maxY - cornerSize)
                for _, line in ipairs(cornersToDraw) do line.Visible = true end
            end
        end
        return true
    end

    function self:cleanup()
        for i = #self.boxes, 1, -1 do
            local espBox = self.boxes[i]
            self:cleanupBox(espBox)
            table.remove(self.boxes, i)
        end
    end

    return self
end

-- HighlightManager module
local HighlightManager = {}
function HighlightManager.new()
    local self = { highlights = {} }

    function self:fadeHighlightOut(highlight, duration)
        if not highlight or not highlight.Parent then return end
        local startFill = highlight.FillTransparency
        local startOutline = 1 -- Always fully transparent
        local t0 = tick()
        local conn
        conn = RunService.RenderStepped:Connect(function()
            local dt = tick() - t0
            local alpha = math.clamp(dt / duration, 0, 1)
            highlight.FillTransparency = startFill + (1 - startFill) * alpha
            highlight.OutlineTransparency = 1
            if alpha >= 1 or not highlight.Parent then
                highlight.Enabled = false
                conn:Disconnect()
            end
        end)
    end

    function self:manageHead(model, dataTable)
        if not espSettings.HeadHighlightEnabled or not isAlive(model) then
            if dataTable and dataTable.HeadH then
                if espSettings.FadeOnDeath and dataTable.HeadH.Parent then
                    self:fadeHighlightOut(dataTable.HeadH, espSettings.FadeDuration)
                else
                    pcall(function() dataTable.HeadH:Destroy() end)
                end
                dataTable.HeadH = nil
            end
            return false
        end
        local headPart = model:FindFirstChild(espSettings.TargetHeadPartName)
        dataTable = dataTable or { HiddenChildParts = {}, HiddenHeadDecals = {} }
        if not headPart or not headPart:IsA("BasePart") then
            if dataTable.HeadH then pcall(function() dataTable.HeadH:Destroy() end); dataTable.HeadH = nil end
            return false
        end
        local headHighlight = dataTable.HeadH
        if not headHighlight or not headHighlight.Parent or headHighlight.Adornee ~= headPart then
            if headHighlight then pcall(function() headHighlight:Destroy() end) end
            headHighlight = Instance.new("Highlight")
            headHighlight.Name = "HeadHighlight_Combined"
            headHighlight.Adornee = headPart
            headHighlight.DepthMode = espSettings.HeadHighlightDepthMode or Enum.HighlightDepthMode.AlwaysOnTop
            headHighlight.FillColor = espSettings.HeadHighlightColor
            headHighlight.OutlineTransparency = 1 -- Always fully transparent
            headHighlight.FillTransparency = espSettings.HeadFillTransparency
            headHighlight.Enabled = true
            headHighlight.Parent = model
            dataTable.HeadH = headHighlight
        end
        -- Always keep outline fully transparent
        pcall(function()
            headHighlight.OutlineColor = espSettings.OutlineColor or Color3.new(0,0,0)
            headHighlight.OutlineTransparency = 1
            headHighlight.FillTransparency = espSettings.HeadFillTransparency
            headHighlight.DepthMode = espSettings.HeadHighlightDepthMode or Enum.HighlightDepthMode.AlwaysOnTop
        end)
        return true
    end

    function self:manageBody(model, dataTable)
        if not espSettings.BodyHighlightEnabled or not isAlive(model) then
            if dataTable and dataTable.BodyH then
                if espSettings.FadeOnDeath and dataTable.BodyH.Parent then
                    self:fadeHighlightOut(dataTable.BodyH, espSettings.FadeDuration)
                else
                    pcall(function() dataTable.BodyH:Destroy() end)
                end
                dataTable.BodyH = nil
            end
            return false
        end
        dataTable = dataTable or { HiddenChildParts = {}, HiddenHeadDecals = {} }
        local bodyHighlight = dataTable.BodyH
        if not bodyHighlight or not bodyHighlight.Parent or bodyHighlight.Adornee ~= model then
            if bodyHighlight then pcall(function() bodyHighlight:Destroy() end) end
            bodyHighlight = Instance.new("Highlight")
            bodyHighlight.Name = "BodyHighlight_Combined"
            bodyHighlight.Adornee = model
            bodyHighlight.DepthMode = espSettings.BodyHighlightDepthMode or Enum.HighlightDepthMode.AlwaysOnTop
            bodyHighlight.FillColor = espSettings.BodyHighlightColor
            bodyHighlight.OutlineTransparency = 1 -- Always fully transparent
            bodyHighlight.FillTransparency = espSettings.BodyFillTransparency
            bodyHighlight.Enabled = true
            bodyHighlight.Parent = model
            dataTable.BodyH = bodyHighlight
        end
        -- Always keep outline fully transparent
        pcall(function()
            bodyHighlight.OutlineColor = espSettings.OutlineColor or Color3.new(0,0,0)
            bodyHighlight.OutlineTransparency = 1
            bodyHighlight.FillTransparency = espSettings.BodyFillTransparency
            bodyHighlight.DepthMode = espSettings.BodyHighlightDepthMode or Enum.HighlightDepthMode.AlwaysOnTop
        end)
        return true
    end

    function self:cleanup()
        for _, h in pairs(self.highlights) do
            if h and h.Parent then
                pcall(function() h:Destroy() end)
            end
        end
        self.highlights = {}
    end

    return self
end

local espBoxManager = ESPBoxManager.new()
local highlightManager = HighlightManager.new()

local activeTargets = {}
local lastScanTime = 0
local TARGET_SCAN_INTERVAL = 0.75
local DEBUG_MODE = false
local renderSteppedConnection = nil

local function DebugPrint(...) if DEBUG_MODE then warn("Combined ESP DBG:", ...) end end

-- Removals: Always scan and apply, independent of chams/ESP
local function ensureRemovalsTables(dataTable)
    if not dataTable.HiddenChildParts then dataTable.HiddenChildParts = {} end
    if not dataTable.HiddenHeadDecals then dataTable.HiddenHeadDecals = {} end
end

local function applyHideChildModels(model, dataTable)
    ensureRemovalsTables(dataTable)
    local headPart = model:FindFirstChild(espSettings.TargetHeadPartName)
    for _, accessory in ipairs(model:GetChildren()) do
        if accessory:IsA("Accessory") then
            local handle = accessory:FindFirstChildWhichIsA("BasePart")
            if handle and handle.Transparency < 1 and not dataTable.HiddenChildParts[handle] then
                dataTable.HiddenChildParts[handle] = handle.Transparency
                handle.Transparency = 1
            end
            for _, part in ipairs(accessory:GetDescendants()) do
                if (part:IsA("BasePart") or part:IsA("Part")) and part.Transparency < 1 and not dataTable.HiddenChildParts[part] then
                    dataTable.HiddenChildParts[part] = part.Transparency
                    part.Transparency = 1
                end
            end
        end
    end
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("Model") and child ~= headPart then
            for _, part in ipairs(child:GetDescendants()) do
                if (part:IsA("BasePart") or part:IsA("Part")) and part.Transparency < 1 and not dataTable.HiddenChildParts[part] then
                    dataTable.HiddenChildParts[part] = part.Transparency
                    part.Transparency = 1
                end
            end
        end
    end
    for _, part in ipairs(model:GetDescendants()) do
        if (part:IsA("BasePart") or part:IsA("Part")) and (part.Name == "FlatTop" or part.Name == "Default" or part.Name == "DefaultHigh") and part.Transparency < 1 and not dataTable.HiddenChildParts[part] then
            dataTable.HiddenChildParts[part] = part.Transparency
            part.Transparency = 1
        end
    end
end

local function restoreHideChildModels(model, dataTable)
    if not dataTable or not dataTable.HiddenChildParts then return end
    for part, origTrans in pairs(dataTable.HiddenChildParts) do
        if part and part.Parent then
            pcall(function() part.Transparency = origTrans end)
        end
    end
    dataTable.HiddenChildParts = {}
end

local function applyHideHeadDecals(model, dataTable)
    ensureRemovalsTables(dataTable)
    local headPart = model:FindFirstChild(espSettings.TargetHeadPartName)
    if not headPart then return end
    for _, decal in ipairs(headPart:GetDescendants()) do
        if decal:IsA("Decal") and decal.Transparency < 1 and not dataTable.HiddenHeadDecals[decal] then
            dataTable.HiddenHeadDecals[decal] = decal.Transparency
            decal.Transparency = 1
        end
    end
end

local function restoreHideHeadDecals(model, dataTable)
    if not dataTable or not dataTable.HiddenHeadDecals then return end
    for decal, origTrans in pairs(dataTable.HiddenHeadDecals) do
        if decal and decal.Parent then
            pcall(function() decal.Transparency = origTrans end)
        end
    end
    dataTable.HiddenHeadDecals = {}
end

-- Removals scan: always runs, not tied to chams/ESP
local function scanForRemovals(cachedWorkspaceChildren)
    local workspaceChildren = cachedWorkspaceChildren or Workspace:GetChildren()
    local foundModels = {}
    for _, instance in ipairs(workspaceChildren) do
        if instance:IsA("Model") and instance.Name == espSettings.TargetParentModelName then
            local model = instance
            local dataTable = activeTargets[model] or {}
            if isRemovalEnabled("Hide Child Models") then
                applyHideChildModels(model, dataTable)
            else
                restoreHideChildModels(model, dataTable)
            end
            if isRemovalEnabled("Hide Head Decals") then
                applyHideHeadDecals(model, dataTable)
            else
                restoreHideHeadDecals(model, dataTable)
            end
            activeTargets[model] = dataTable
            foundModels[model] = true
        end
    end
    -- Clean up removals for models no longer present
    for model, dataTable in pairs(activeTargets) do
        if not foundModels[model] then
            restoreHideChildModels(model, dataTable)
            restoreHideHeadDecals(model, dataTable)
        end
    end
end

RunService:BindToRenderStep("RemovalsUpdate", Enum.RenderPriority.Camera.Value + 2, function()
    local cachedWorkspaceChildren = Workspace:GetChildren()
    pcall(scanForRemovals, cachedWorkspaceChildren)
end)

-- Distance ESP Drawing
local distanceDrawings = {}

local function cleanupDistanceESP()
    for _, drawing in pairs(distanceDrawings) do
        if drawing.Remove then drawing:Remove() end
    end
    distanceDrawings = {}
end

local function updateDistanceESP(model, primaryPart)
    if not espSettings.DistanceESPEnabled then return end
    if not primaryPart then return end
    local camPos = Camera.CFrame.Position
    local distance = (camPos - primaryPart.Position).Magnitude
    local screenPoint, onScreen = Camera:WorldToViewportPoint(primaryPart.Position)
    if not onScreen then return end

    local drawing = distanceDrawings[model]
    if not drawing then
        drawing = DrawingManager:add(Drawing.new("Text"))
        drawing.Center = true
        drawing.Outline = false
        distanceDrawings[model] = drawing
    end
    drawing.Size = espSettings.DistanceESPSize
    drawing.Color = espSettings.DistanceESPColor
    drawing.Position = Vector2.new(screenPoint.X, screenPoint.Y + 25)
    drawing.Text = string.format("%.1f studs", distance)
    drawing.Visible = true
end

local function restoreChildModelParts(model, dataTable)
    if not dataTable or not dataTable.HiddenChildParts then return end
    for part, origTrans in pairs(dataTable.HiddenChildParts) do
        if part and part.Parent then
            pcall(function() part.Transparency = origTrans end)
        end
    end
    dataTable.HiddenChildParts = {}
end

local function restoreHeadDecals(headPart, dataTable)
    if not dataTable or not dataTable.HiddenHeadDecals then return end
    for decal, origTrans in pairs(dataTable.HiddenHeadDecals) do
        if decal and decal.Parent then
            pcall(function() decal.Transparency = origTrans end)
        end
    end
    dataTable.HiddenHeadDecals = {}
end

local function cleanupCombinedESPTarget(model)
    local targetData = activeTargets[model]; if not targetData then return end
    if targetData.HeadH then pcall(function() targetData.HeadH:Destroy() end) end
    if targetData.BodyH then pcall(function() targetData.BodyH:Destroy() end) end
    restoreChildModelParts(model, targetData)
    local headPart = model:FindFirstChild(espSettings.TargetHeadPartName)
    if headPart then restoreHeadDecals(headPart, targetData) end
    activeTargets[model] = nil
end

local function validateCombinedESPHighlights()
    if not espSettings.CombinedESPEnabled then return end
    if not player or not Camera or not Camera.Parent then return end
    local modelsToCleanup = {}
    for model, targetData in pairs(activeTargets) do
        local modelStillValid = model and model:IsDescendantOf(Workspace)
        if not modelStillValid then
            table.insert(modelsToCleanup, model)
        else
            local headPart = model:FindFirstChild(espSettings.TargetHeadPartName)
            if targetData.HeadH then
                if not targetData.HeadH.Parent or not headPart or targetData.HeadH.Adornee ~= headPart then
                    pcall(function() targetData.HeadH:Destroy() end)
                    targetData.HeadH = nil
                end
            end
            if targetData.BodyH then
                if not targetData.BodyH.Parent or targetData.BodyH.Adornee ~= model then
                    pcall(function() targetData.BodyH:Destroy() end)
                    targetData.BodyH = nil
                end
            end
            if not targetData.HeadH and not targetData.BodyH then
                table.insert(modelsToCleanup, model)
            end
        end
    end
    for _, modelToRemove in ipairs(modelsToCleanup) do
        cleanupCombinedESPTarget(modelToRemove)
    end
end

local function scanForCombinedESPTargets(cachedWorkspaceChildren, cachedDescendantsMap)
    if not espSettings.CombinedESPEnabled then return end
    local foundInScan = {}
    local workspaceChildren = cachedWorkspaceChildren or Workspace:GetChildren()
    for _, instance in ipairs(workspaceChildren) do
        if instance:IsA("Model") and instance.Name == espSettings.TargetParentModelName then
            local model = instance; local dataTable = activeTargets[model] or { HiddenChildParts = {}, HiddenHeadDecals = {} }
            local headPart = model:FindFirstChild(espSettings.TargetHeadPartName)
            if headPart and headPart:IsA("BasePart") then
                highlightManager:manageHead(model, dataTable)
                highlightManager:manageBody(model, dataTable)
                foundInScan[model] = true
            else
                cleanupCombinedESPTarget(model)
            end
            if dataTable.HeadH or dataTable.BodyH then activeTargets[model] = dataTable else activeTargets[model] = nil end
        end
    end
    for model, _ in pairs(activeTargets) do if not foundInScan[model] then cleanupCombinedESPTarget(model) end end
end

local function updateESP()
    local cachedWorkspaceChildren = Workspace:GetChildren()
    local cachedDescendantsMap = {}
    for _, model in ipairs(cachedWorkspaceChildren) do
        if model:IsA("Model") then
            cachedDescendantsMap[model] = model:GetDescendants()
        end
    end

    espBoxManager:updateBoxes(cachedWorkspaceChildren, cachedDescendantsMap)

    local currentTime = tick()
    if currentTime - lastScanTime >= TARGET_SCAN_INTERVAL then
        lastScanTime = currentTime
        pcall(scanForCombinedESPTargets, cachedWorkspaceChildren, cachedDescendantsMap)
    end

    -- Distance ESP
    if espSettings.DistanceESPEnabled then
        for _, espBox in ipairs(espBoxManager.boxes) do
            local model = espBox.Model
            if model and model.Parent then
                local primaryPart = model.PrimaryPart or (model:FindFirstChild(espSettings.TargetHeadPartName) or model:FindFirstChildWhichIsA("BasePart"))
                updateDistanceESP(model, primaryPart)
            end
        end
    else
        cleanupDistanceESP()
    end
end

local function cleanupAllESPFeatures()
    DebugPrint("Cleaning up ALL ESP features...")
    espBoxManager:cleanup()
    local modelsToCleanup = {}
    for model, _ in pairs(activeTargets) do table.insert(modelsToCleanup, model) end
    for _, model in ipairs(modelsToCleanup) do cleanupCombinedESPTarget(model) end
    cleanupDistanceESP()
    DrawingManager:cleanup()
    DebugPrint("Full ESP cleanup finished.")
end

-- // --- UI Definition (Tokyo Lib) --- \ --
local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/drillygzzly/Roblox-UI-Libs/main/1%20Tokyo%20Lib%20(FIXED)/Tokyo%20Lib%20Source.lua"))({
    cheatname = "Chams",
    gamename = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or "Unknown Game",
})

local function copyToClipboard(text) setclipboard(text); library:SendNotification("Link copied!", 3) end

library:init()

local Window = library.NewWindow({ title = "OvErVoLtAgE v.2", size = UDim2.new(0, 510, 0.7, 6) })
local VisualsTab = Window:AddTab("  Visuals  ")
local SettingsTab = library:CreateSettingsTab(Window)

-- Box ESP Section
local BoxESPSection = VisualsTab:AddSection("Box ESP", 1)
BoxESPSection:AddToggle({
    text = "Enable", state = espSettings.BoxEnabled, flag = "BoxESPEnabled", tooltip = "Draw 2D boxes around targets",
    callback = function(state)
        if type(state) == "boolean" then
            espSettings.BoxEnabled = state
            if not state then
                for i=#espBoxManager.boxes,1,-1 do
                    for _,l in pairs(espBoxManager.boxes[i].Lines) do l.Visible=false end
                end
            end
        else
            warn("Invalid Box ESP state:", state)
        end
    end
})
BoxESPSection:AddList({
    text = "Box Style", tooltip = "Style of the 2D box", values = {"Classic", "Corners"}, selected = espSettings.BoxStyle, flag = "BoxStyle",
    callback = function(value)
        if value == "Classic" or value == "Corners" then
            espSettings.BoxStyle = value
        else
            warn("Invalid Box Style value:", value)
        end
    end
})
BoxESPSection:AddSlider({
    text = "Corner length", flag = "BoxCornerSize", suffix = "px", min = 3, max = 20, increment = 1, value = espSettings.CornerSize, tooltip = "Length of corners if using Corners style",
    callback = function(value)
        if type(value) == "number" and value >= 3 and value <= 20 then
            espSettings.CornerSize = value
        else
            warn("Invalid Corner length value:", value)
        end
    end
})
BoxESPSection:AddSlider({
    text = "Box Thickness", flag = "BoxThickness", suffix = "px", min = 1, max = 10, increment = 1, value = espSettings.BoxThickness, tooltip = "Line thickness for the box",
    callback = function(value)
        if type(value) == "number" and value >= 1 and value <= 10 then
            espSettings.BoxThickness = value
        else
            warn("Invalid Box Thickness value:", value)
        end
    end
})
BoxESPSection:AddSlider({
    text = "Box Transparency", flag = "BoxTransparency", suffix = "", min = 0, max = 1, increment = 0.05, value = espSettings.BoxTransparency, tooltip = "Transparency of the box lines",
    callback = function(value)
        if type(value) == "number" and value >= 0 and value <= 1 then
            espSettings.BoxTransparency = value
        else
            warn("Invalid Box Transparency value:", value)
        end
    end
})
BoxESPSection:AddColor({
    text = "Box Color", color = espSettings.BoxColor, flag = "BoxColor", tooltip = "Color of the box lines",
    callback = function(color)
        if typeof(color) == "Color3" then
            espSettings.BoxColor = color
        else
            warn("Invalid Box Color value:", color)
        end
    end
})

-- Combined ESP Section
local CombinedESPSection = VisualsTab:AddSection("Chams", 2)
CombinedESPSection:AddToggle({
    text = "Enable", state = espSettings.CombinedESPEnabled, flag = "CombinedESPEnabled", tooltip = "Render player through walls",
    callback = function(state)
        if type(state) == "boolean" then
            espSettings.CombinedESPEnabled = state
            if not state then cleanupAllESPFeatures() end
        else
            warn("Invalid Combined ESP state:", state)
        end
    end
})
CombinedESPSection:AddToggle({
    text = "Head Chams", state = espSettings.HeadHighlightEnabled, flag = "HeadHighlightEnabled", tooltip = "Show green highlight on head (Req. Combined)",
    callback = function(state)
        if type(state) == "boolean" then
            espSettings.HeadHighlightEnabled = state
            if not state then
                for _,d in pairs(activeTargets) do
                    if d.HeadH then pcall(function() d.HeadH:Destroy() end); d.HeadH=nil end
                end
            end
        else
            warn("Invalid Head Highlight Enabled value:", state)
        end
    end
})
CombinedESPSection:AddSlider({
    text = "Head Fill Transparency", flag = "HeadFillTransparency", min = 0, max = 1, increment = 0.01, value = espSettings.HeadFillTransparency, tooltip = "Transparency for head highlight fill",
    callback = function(value)
        if type(value) == "number" and value >= 0 and value <= 1 then
            espSettings.HeadFillTransparency = value
        else
            warn("Invalid Head Fill Transparency value:", value)
        end
    end
})
CombinedESPSection:AddColor({
    text = "Head Fill Color", color = espSettings.HeadHighlightColor, flag = "HeadHighlightColor", tooltip = "Color for head highlight",
    callback = function(color)
        if typeof(color) == "Color3" then
            espSettings.HeadHighlightColor = color
        else
            warn("Invalid Head Highlight Color value:", color)
        end
    end
})
CombinedESPSection:AddList({
    text = "Head Highlight Depth Mode",
    tooltip = "Change how head highlights appear through walls",
    values = {"AlwaysOnTop", "Occluded"},
    selected = tostring(espSettings.HeadHighlightDepthMode) == "Enum.HighlightDepthMode.Occluded" and "Occluded" or "AlwaysOnTop",
    flag = "HeadHighlightDepthMode",
    callback = function(value)
        if value == "AlwaysOnTop" then
            espSettings.HeadHighlightDepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        else
            espSettings.HeadHighlightDepthMode = Enum.HighlightDepthMode.Occluded
        end
    end
})
CombinedESPSection:AddToggle({
    text = "Body Chams", state = espSettings.BodyHighlightEnabled, flag = "BodyHighlightEnabled", tooltip = "Show red highlight on body (Req. Combined)",
    callback = function(state)
        if type(state) == "boolean" then
            espSettings.BodyHighlightEnabled = state
            if not state then
                for _,d in pairs(activeTargets) do
                    if d.BodyH then pcall(function() d.BodyH:Destroy() end); d.BodyH=nil end
                end
            end
        else
            warn("Invalid Body Highlight Enabled value:", state)
        end
    end
})
CombinedESPSection:AddSlider({
    text = "Body Fill Transparency", flag = "BodyFillTransparency", min = 0, max = 1, increment = 0.01, value = espSettings.BodyFillTransparency, tooltip = "Transparency for body highlight fill",
    callback = function(value)
        if type(value) == "number" and value >= 0 and value <= 1 then
            espSettings.BodyFillTransparency = value
        else
            warn("Invalid Body Fill Transparency value:", value)
        end
    end
})
CombinedESPSection:AddColor({
    text = "Body Fill Color", color = espSettings.BodyHighlightColor, flag = "BodyHighlightColor", tooltip = "Color for body highlight",
    callback = function(color)
        if typeof(color) == "Color3" then
            espSettings.BodyHighlightColor = color
        else
            warn("Invalid Body Highlight Color value:", color)
        end
    end
})
CombinedESPSection:AddList({
    text = "Body Highlight Depth Mode",
    tooltip = "Change how body highlights appear through walls",
    values = {"AlwaysOnTop", "Occluded"},
    selected = tostring(espSettings.BodyHighlightDepthMode) == "Enum.HighlightDepthMode.Occluded" and "Occluded" or "AlwaysOnTop",
    flag = "BodyHighlightDepthMode",
    callback = function(value)
        if value == "AlwaysOnTop" then
            espSettings.BodyHighlightDepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        else
            espSettings.BodyHighlightDepthMode = Enum.HighlightDepthMode.Occluded
        end
    end
})
CombinedESPSection:AddToggle({
    text = "Distance ESP",
    state = espSettings.DistanceESPEnabled,
    flag = "DistanceESPEnabled",
    tooltip = "Show distance below ESP box",
    callback = function(state)
        espSettings.DistanceESPEnabled = state
        if not state then cleanupDistanceESP() end
    end
})
CombinedESPSection:AddSlider({
    text = "Distance ESP Size",
    flag = "DistanceESPSize",
    min = 12, max = 64, increment = 1, value = espSettings.DistanceESPSize,
    tooltip = "Font size for distance ESP",
    callback = function(value)
        espSettings.DistanceESPSize = value
    end
})
CombinedESPSection:AddColor({
    text = "Distance ESP Color",
    color = espSettings.DistanceESPColor,
    flag = "DistanceESPColor",
    tooltip = "Color for distance ESP text",
    callback = function(color)
        if typeof(color) == "Color3" then
            espSettings.DistanceESPColor = color
        end
    end
})
CombinedESPSection:AddToggle({
    text = "Fade-out on Death",
    state = espSettings.FadeOnDeath,
    flag = "FadeOnDeath",
    tooltip = "Fade out chams when player dies/ragdolls",
    callback = function(state)
        espSettings.FadeOnDeath = state
    end
})
CombinedESPSection:AddSlider({
    text = "Fade Duration",
    flag = "FadeDuration",
    min = 0.1, max = 2, increment = 0.05, value = espSettings.FadeDuration,
    tooltip = "Duration of fade-out (seconds)",
    callback = function(value)
        espSettings.FadeDuration = value
    end
})

-- Removals Section (now separate)
local RemovalsSection = VisualsTab:AddSection("Removals", 3)
RemovalsSection:AddList({
    text = "Removals",
    tooltip = "Select which removals to apply (multi-select)",
    values = {"Hide Child Models", "Hide Head Decals"},
    multi = true,
    selected = espSettings.Removals,
    flag = "Removals",
    callback = function(selected)
        if typeof(selected) == "table" then
            espSettings.Removals = selected
            -- Restore if removals are unchecked (handled by scanForRemovals loop)
        else
            warn("Invalid Removals selection:", selected)
        end
    end
})

renderSteppedConnection = RunService:BindToRenderStep("CombinedESPUpdate", Enum.RenderPriority.Camera.Value + 1, function()
    local success, err = pcall(updateESP)
    if not success then warn("ESP Update Error:", err) end

    local success2, err2 = pcall(validateCombinedESPHighlights)
    if not success2 then warn("Combined Validate Error:", err2) end
end)


local AimbotTab = Window:AddTab("  Aimbot  ")
local aimbotEnabled = false
local aiming = false
local aimbotSmoothing = 0.25 -- Default smoothing (0.05 = slow, 1 = instant)

local AimbotSection = AimbotTab:AddSection("Aimbot", 1)
AimbotSection:AddToggle({
    text = "Enable Aimbot",
    state = aimbotEnabled,
    flag = "AimbotEnabled",
    tooltip = "Hold right mouse to lock cursor onto the closest ESP head.",
    callback = function(state)
        aimbotEnabled = state
    end
})
AimbotSection:AddSlider({
    text = "Smoothing",
    flag = "AimbotSmoothing",
    min = 0.05, max = 1, increment = 0.01, value = aimbotSmoothing,
    tooltip = "Speed of moving cursor towards head (lower = slower, higher = snappier)",
    callback = function(value)
        aimbotSmoothing = value
    end
})

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Input handling: Hold right mouse button to aim
UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.UserInputType == Enum.UserInputType.MouseButton2 then
        aiming = true
    end
end)
UserInputService.InputEnded:Connect(function(input, processed)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        aiming = false
    end
end)

-- Find the closest ESP target's head (uses the same settings as ESP/Chams)
local function getClosestESPHead()
    local closestPart = nil
    local closestDist = math.huge
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    for _, model in ipairs(workspace:GetChildren()) do
        if model:IsA("Model") and model.Name == espSettings.TargetParentModelName and model.Parent and isAlive(model) then
            local head = model:FindFirstChild(espSettings.TargetHeadPartName)
            if head and head:IsA("BasePart") then
                local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closestPart = head
                    end
                end
            end
        end
    end
    return closestPart
end

-- Main loop: Smoothly move cursor to head's screen position
RunService.RenderStepped:Connect(function()
    if aimbotEnabled and aiming and Camera then
        local target = getClosestESPHead()
        if target and typeof(target.Position) == "Vector3" then
            local screenPos, onScreen = Camera:WorldToViewportPoint(target.Position)
            if onScreen then
                local mousePos = UserInputService:GetMouseLocation()
                local relX = screenPos.X - mousePos.X
                local relY = screenPos.Y - mousePos.Y
                local dist = math.sqrt(relX * relX + relY * relY)
                local threshold = 3 -- pixels, snap if closer than this
                if dist > threshold then
                    -- Smoothing: move at most a fraction, but clamp to not overshoot
                    local moveX = math.abs(relX) < threshold and relX or relX * aimbotSmoothing
                    local moveY = math.abs(relY) < threshold and relY or relY * aimbotSmoothing
                    -- Clamp move to not overshoot
                    if math.abs(moveX) > math.abs(relX) then moveX = relX end
                    if math.abs(moveY) > math.abs(relY) then moveY = relY end
                    if mousemoverel then
                        mousemoverel(moveX, moveY)
                    elseif mousemoveabs then
                        mousemoveabs(mousePos.X + moveX, mousePos.Y + moveY)
                    end
                else
                    -- Snap directly if close enough
                    if mousemoverel then
                        mousemoverel(relX, relY)
                    elseif mousemoveabs then
                        mousemoveabs(screenPos.X, screenPos.Y)
                    end
                end
            end
        end
    end
end)

print("Combined ESP Script with TokyoLib UI Loaded. Scan Interval:", TARGET_SCAN_INTERVAL)
task.spawn(scanForCombinedESPTargets)
