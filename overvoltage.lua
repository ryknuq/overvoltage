local function isValidNPC(model)
    if model:IsA("Model") and model.Name == "Male" then
        for _, child in ipairs(model:GetChildren()) do
            if child:IsA("Model") and child.Name:sub(1, 3) == "AI_" then
                return true
            end
        end
    end
    return false
end

-- === ESP CONSTANTS ===
local ESP_CONSTANTS = {
    TARGET_PARENT_MODEL_NAME = "Male",
    TARGET_HEAD_PART_NAME = "Head",
    REMOVAL_TYPES = {
        HIDE_CHILD_MODELS = "Hide Child Models",
        HIDE_HEAD_DECALS = "Hide Head Decals"
    }
}

local Decimals = 4
local Clock = os.clock()

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
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
    TargetParentModelName = ESP_CONSTANTS.TARGET_PARENT_MODEL_NAME,
    TargetHeadPartName = ESP_CONSTANTS.TARGET_HEAD_PART_NAME,

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

-- DrawingManager class using metatables
local DrawingManager = {}
DrawingManager.__index = DrawingManager

function DrawingManager.new()
    local self = setmetatable({objects = {}}, DrawingManager)
    return self
end

function DrawingManager:add(obj)
    table.insert(self.objects, obj)
    return obj
end

function DrawingManager:cleanup()
    for _, obj in ipairs(self.objects) do
        if obj.Remove then
            if obj and typeof(obj) == "Instance" and obj.Parent then
                obj:Remove()
            else
                pcall(function() obj:Remove() end)
            end
        end
    end
    self.objects = {}
end

local drawingManager = DrawingManager.new()

-- ESPBoxManager class using metatables
local ESPBoxManager = {}
ESPBoxManager.__index = ESPBoxManager

function ESPBoxManager.new()
    local self = setmetatable({boxes = {}}, ESPBoxManager)

    local lineNames = {"TopLine", "LeftLine", "RightLine", "BottomLine",
        "TopLeftCorner1", "TopLeftCorner2", "TopRightCorner1", "TopRightCorner2",
        "BottomLeftCorner1", "BottomLeftCorner2", "BottomRightCorner1", "BottomRightCorner2"}

    function self:createBox(model)
        local espBox = { Model = model }
        espBox.Lines = {}
        for _, name in ipairs(lineNames) do
            local line = drawingManager:add(Drawing.new("Line"))
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
            if line and typeof(line) == "Instance" and line.Parent then
                line:Remove()
            elseif line and line.Remove then
                pcall(function() line:Remove() end)
            end
        end
        espBox.Lines = nil
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
                if object:IsA("Model") and object.Name == ESP_CONSTANTS.TARGET_PARENT_MODEL_NAME and not currentBoxes[object] then
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

-- HighlightManager class using metatables
local HighlightManager = {}
HighlightManager.__index = HighlightManager

function HighlightManager.new()
    local self = setmetatable({highlights = {}}, HighlightManager)

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
                    if dataTable.HeadH and typeof(dataTable.HeadH) == "Instance" and dataTable.HeadH.Parent then
                        dataTable.HeadH:Destroy()
                    else
                        pcall(function() dataTable.HeadH:Destroy() end)
                    end
                end
                dataTable.HeadH = nil
            end
            return false
        end
        local headPart = model:FindFirstChild(ESP_CONSTANTS.TARGET_HEAD_PART_NAME)
        dataTable = dataTable or { HiddenChildParts = {}, HiddenHeadDecals = {} }
        if not headPart or not headPart:IsA("BasePart") then
            if dataTable.HeadH and typeof(dataTable.HeadH) == "Instance" and dataTable.HeadH.Parent then dataTable.HeadH:Destroy(); dataTable.HeadH = nil end
            return false
        end
        local headHighlight = dataTable.HeadH
        if not headHighlight or not headHighlight.Parent or headHighlight.Adornee ~= headPart then
            if headHighlight and typeof(headHighlight) == "Instance" and headHighlight.Parent then headHighlight:Destroy() end
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
        if headHighlight then
            headHighlight.OutlineColor = espSettings.OutlineColor or Color3.new(0,0,0)
            headHighlight.OutlineTransparency = 1
            headHighlight.FillTransparency = espSettings.HeadFillTransparency
            headHighlight.DepthMode = espSettings.HeadHighlightDepthMode or Enum.HighlightDepthMode.AlwaysOnTop
        end
        return true
    end

    function self:manageBody(model, dataTable)
        if not espSettings.BodyHighlightEnabled or not isAlive(model) then
            if dataTable and dataTable.BodyH then
                if espSettings.FadeOnDeath and dataTable.BodyH.Parent then
                    self:fadeHighlightOut(dataTable.BodyH, espSettings.FadeDuration)
                else
                    if dataTable.BodyH and typeof(dataTable.BodyH) == "Instance" and dataTable.BodyH.Parent then
                        dataTable.BodyH:Destroy()
                    else
                        pcall(function() dataTable.BodyH:Destroy() end)
                    end
                end
                dataTable.BodyH = nil
            end
            return false
        end
        dataTable = dataTable or { HiddenChildParts = {}, HiddenHeadDecals = {} }
        local bodyHighlight = dataTable.BodyH
        if not bodyHighlight or not bodyHighlight.Parent or bodyHighlight.Adornee ~= model then
            if bodyHighlight and typeof(bodyHighlight) == "Instance" and bodyHighlight.Parent then bodyHighlight:Destroy() end
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
        if bodyHighlight then
            bodyHighlight.OutlineColor = espSettings.OutlineColor or Color3.new(0,0,0)
            bodyHighlight.OutlineTransparency = 1
            bodyHighlight.FillTransparency = espSettings.BodyFillTransparency
            bodyHighlight.DepthMode = espSettings.BodyHighlightDepthMode or Enum.HighlightDepthMode.AlwaysOnTop
        end
        return true
    end

    function self:cleanup()
        for _, h in pairs(self.highlights) do
            if h and typeof(h) == "Instance" and h.Parent then
                h:Destroy()
            else
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
    local headPart = model:FindFirstChild(ESP_CONSTANTS.TARGET_HEAD_PART_NAME)
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
            part.Transparency = origTrans
        end
    end
    dataTable.HiddenChildParts = {}
end

local function applyHideHeadDecals(model, dataTable)
    ensureRemovalsTables(dataTable)
    local headPart = model:FindFirstChild(ESP_CONSTANTS.TARGET_HEAD_PART_NAME)
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
            decal.Transparency = origTrans
        end
    end
    dataTable.HiddenHeadDecals = {}
end

-- Removals scan: always runs, not tied to chams/ESP
local function scanForRemovals(cachedWorkspaceChildren)
    local workspaceChildren = cachedWorkspaceChildren or Workspace:GetChildren()
    local foundModels = {}
    for _, instance in ipairs(workspaceChildren) do
       -- if instance:IsA("Model") and instance.Name == ESP_CONSTANTS.TARGET_PARENT_MODEL_NAME then
       if isValidNPC(instance) then
            local model = instance
            local dataTable = activeTargets[model] or {}
            if isRemovalEnabled(ESP_CONSTANTS.REMOVAL_TYPES.HIDE_CHILD_MODELS) then
                applyHideChildModels(model, dataTable)
            else
                restoreHideChildModels(model, dataTable)
            end
            if isRemovalEnabled(ESP_CONSTANTS.REMOVAL_TYPES.HIDE_HEAD_DECALS) then
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
        if drawing.Remove then
            if drawing and typeof(drawing) == "Instance" and drawing.Parent then
                drawing:Remove()
            else
                pcall(function() drawing:Remove() end)
            end
        end
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
        drawing = drawingManager:add(Drawing.new("Text"))
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
            part.Transparency = origTrans
        end
    end
    dataTable.HiddenChildParts = {}
end

local function restoreHeadDecals(headPart, dataTable)
    if not dataTable or not dataTable.HiddenHeadDecals then return end
    for decal, origTrans in pairs(dataTable.HiddenHeadDecals) do
        if decal and decal.Parent then
            decal.Transparency = origTrans
        end
    end
    dataTable.HiddenHeadDecals = {}
end

local function cleanupCombinedESPTarget(model)
    local targetData = activeTargets[model]; if not targetData then return end
    if targetData.HeadH and typeof(targetData.HeadH) == "Instance" and targetData.HeadH.Parent then targetData.HeadH:Destroy() end
    if targetData.BodyH and typeof(targetData.BodyH) == "Instance" and targetData.BodyH.Parent then targetData.BodyH:Destroy() end
    restoreChildModelParts(model, targetData)
    local headPart = model:FindFirstChild(ESP_CONSTANTS.TARGET_HEAD_PART_NAME)
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
            local headPart = model:FindFirstChild(ESP_CONSTANTS.TARGET_HEAD_PART_NAME)
            if targetData.HeadH then
                if not targetData.HeadH.Parent or not headPart or targetData.HeadH.Adornee ~= headPart then
                    if targetData.HeadH and typeof(targetData.HeadH) == "Instance" and targetData.HeadH.Parent then
                        targetData.HeadH:Destroy()
                    else
                        pcall(function() targetData.HeadH:Destroy() end)
                    end
                    targetData.HeadH = nil
                end
            end
            if targetData.BodyH then
                if not targetData.BodyH.Parent or targetData.BodyH.Adornee ~= model then
                    if targetData.BodyH and typeof(targetData.BodyH) == "Instance" and targetData.BodyH.Parent then
                        targetData.BodyH:Destroy()
                    else
                        pcall(function() targetData.BodyH:Destroy() end)
                    end
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
       --if instance:IsA("Model") and instance.Name == ESP_CONSTANTS.TARGET_PARENT_MODEL_NAME then 
       if isValidNPC(instance) then
            local model = instance; local dataTable = activeTargets[model] or { HiddenChildParts = {}, HiddenHeadDecals = {} }
            local headPart = model:FindFirstChild(ESP_CONSTANTS.TARGET_HEAD_PART_NAME)
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

-- === Caching Workspace Children and Descendants ===
local cachedWorkspaceChildren = {}
local cachedDescendantsMap = {}
local lastCacheUpdate = 0
local CACHE_UPDATE_INTERVAL = 0.5

local function updateCaches()
    cachedWorkspaceChildren = Workspace:GetChildren()
    cachedDescendantsMap = {}
    for _, model in ipairs(cachedWorkspaceChildren) do
        if model:IsA("Model") then
            cachedDescendantsMap[model] = model:GetDescendants()
        end
    end
end

local function updateESP(cachedWorkspaceChildren, cachedDescendantsMap)
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
                local primaryPart = model.PrimaryPart or (model:FindFirstChild(ESP_CONSTANTS.TARGET_HEAD_PART_NAME) or model:FindFirstChildWhichIsA("BasePart"))
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
    drawingManager:cleanup()
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
        -- Sanitize and validate input
        if typeof(value) ~= "number" then
            warn("Corner length must be a number, got:", typeof(value))
            return
        end
        value = math.clamp(math.floor(value), 3, 20)
        espSettings.CornerSize = value
    end
})
BoxESPSection:AddSlider({
    text = "Box Thickness", flag = "BoxThickness", suffix = "px", min = 1, max = 10, increment = 1, value = espSettings.BoxThickness, tooltip = "Line thickness for the box",
    callback = function(value)
        -- Sanitize and validate input
        if typeof(value) ~= "number" then
            warn("Box Thickness must be a number, got:", typeof(value))
            return
        end
        value = math.clamp(math.floor(value), 1, 10)
        espSettings.BoxThickness = value
    end
})
BoxESPSection:AddSlider({
    text = "Box Transparency", flag = "BoxTransparency", suffix = "", min = 0, max = 1, increment = 0.05, value = espSettings.BoxTransparency, tooltip = "Transparency of the box lines",
    callback = function(value)
        -- Sanitize and validate input
        if typeof(value) ~= "number" then
            warn("Box Transparency must be a number, got:", typeof(value))
            return
        end
        value = math.clamp(value, 0, 1)
        espSettings.BoxTransparency = value
    end
})
BoxESPSection:AddColor({
    text = "Box Color", color = espSettings.BoxColor, flag = "BoxColor", tooltip = "Color of the box lines",
    callback = function(color)
        -- Sanitize and validate input
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
                    if d.HeadH and typeof(d.HeadH) == "Instance" and d.HeadH.Parent then d.HeadH:Destroy(); d.HeadH=nil end
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
        -- Sanitize and validate input
        if typeof(value) ~= "number" then
            warn("Head Fill Transparency must be a number, got:", typeof(value))
            return
        end
        value = math.clamp(value, 0, 1)
        espSettings.HeadFillTransparency = value
    end
})
CombinedESPSection:AddColor({
    text = "Head Fill Color", color = espSettings.HeadHighlightColor, flag = "HeadHighlightColor", tooltip = "Color for head highlight",
    callback = function(color)
        -- Sanitize and validate input
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
        elseif value == "Occluded" then
            espSettings.HeadHighlightDepthMode = Enum.HighlightDepthMode.Occluded
        else
            warn("Invalid Head Highlight Depth Mode value:", value)
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
                    if d.BodyH and typeof(d.BodyH) == "Instance" and d.BodyH.Parent then d.BodyH:Destroy(); d.BodyH=nil end
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
        -- Sanitize and validate input
        if typeof(value) ~= "number" then
            warn("Body Fill Transparency must be a number, got:", typeof(value))
            return
        end
        value = math.clamp(value, 0, 1)
        espSettings.BodyFillTransparency = value
    end
})
CombinedESPSection:AddColor({
    text = "Body Fill Color", color = espSettings.BodyHighlightColor, flag = "BodyHighlightColor", tooltip = "Color for body highlight",
    callback = function(color)
        -- Sanitize and validate input
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
        elseif value == "Occluded" then
            espSettings.BodyHighlightDepthMode = Enum.HighlightDepthMode.Occluded
        else
            warn("Invalid Body Highlight Depth Mode value:", value)
        end
    end
})
CombinedESPSection:AddToggle({
    text = "Distance ESP",
    state = espSettings.DistanceESPEnabled,
    flag = "DistanceESPEnabled",
    tooltip = "Show distance below ESP box",
    callback = function(state)
        if type(state) == "boolean" then
            espSettings.DistanceESPEnabled = state
            if not state then cleanupDistanceESP() end
        else
            warn("Invalid Distance ESP state:", state)
        end
    end
})
CombinedESPSection:AddSlider({
    text = "Distance ESP Size",
    flag = "DistanceESPSize",
    min = 12, max = 64, increment = 1, value = espSettings.DistanceESPSize,
    tooltip = "Font size for distance ESP",
    callback = function(value)
        -- Sanitize and validate input
        if typeof(value) ~= "number" then
            warn("Distance ESP Size must be a number, got:", typeof(value))
            return
        end
        value = math.clamp(math.floor(value), 12, 64)
        espSettings.DistanceESPSize = value
    end
})
CombinedESPSection:AddColor({
    text = "Distance ESP Color",
    color = espSettings.DistanceESPColor,
    flag = "DistanceESPColor",
    tooltip = "Color for distance ESP text",
    callback = function(color)
        -- Sanitize and validate input
        if typeof(color) == "Color3" then
            espSettings.DistanceESPColor = color
        else
            warn("Invalid Distance ESP Color value:", color)
        end
    end
})
CombinedESPSection:AddToggle({
    text = "Fade-out on Death",
    state = espSettings.FadeOnDeath,
    flag = "FadeOnDeath",
    tooltip = "Fade out chams when player dies/ragdolls",
    callback = function(state)
        if type(state) == "boolean" then
            espSettings.FadeOnDeath = state
        else
            warn("Invalid FadeOnDeath value:", state)
        end
    end
})
CombinedESPSection:AddSlider({
    text = "Fade Duration",
    flag = "FadeDuration",
    min = 0.1, max = 2, increment = 0.05, value = espSettings.FadeDuration,
    tooltip = "Duration of fade-out (seconds)",
    callback = function(value)
        -- Sanitize and validate input
        if typeof(value) ~= "number" then
            warn("Fade Duration must be a number, got:", typeof(value))
            return
        end
        value = math.clamp(value, 0.1, 2)
        espSettings.FadeDuration = value
    end
})

-- Removals Section (now separate)
local RemovalsSection = VisualsTab:AddSection("Removals", 3)
RemovalsSection:AddList({
    text = "Removals",
    tooltip = "Select which removals to apply (multi-select)",
    values = {ESP_CONSTANTS.REMOVAL_TYPES.HIDE_CHILD_MODELS, ESP_CONSTANTS.REMOVAL_TYPES.HIDE_HEAD_DECALS},
    multi = true,
    selected = espSettings.Removals,
    flag = "Removals",
    callback = function(selected)
        -- Sanitize and validate input
        if typeof(selected) == "table" then
            local valid = true
            for _, v in ipairs(selected) do
                if v ~= ESP_CONSTANTS.REMOVAL_TYPES.HIDE_CHILD_MODELS and v ~= ESP_CONSTANTS.REMOVAL_TYPES.HIDE_HEAD_DECALS then
                    valid = false
                    break
                end
            end
            if valid then
                espSettings.Removals = selected
            else
                warn("Invalid Removals selection:", selected)
            end
        else
            warn("Invalid Removals selection:", selected)
        end
    end
})

renderSteppedConnection = RunService:BindToRenderStep("CombinedESPUpdate", Enum.RenderPriority.Camera.Value + 1, function()
    if tick() - lastCacheUpdate > CACHE_UPDATE_INTERVAL then
        updateCaches()
        lastCacheUpdate = tick()
    end
    local success, err = pcall(function() updateESP(cachedWorkspaceChildren, cachedDescendantsMap) end)
    if not success then warn("ESP Update Error:", err) end

    local success2, err2 = pcall(validateCombinedESPHighlights)
    if not success2 then warn("Combined Validate Error:", err2) end
end)

-- === Aimbot & Triggerbot Tab ===
local AimbotTab = Window:AddTab("  Aimbot  ")
local AimbotSection = AimbotTab:AddSection("Aimbot", 1)
local TriggerbotSection = AimbotTab:AddSection("Triggerbot", 2)

-- Triggerbot settings
local triggerbotEnabled = false
local triggerbotWallCheck = true -- NEW: triggerbot wallcheck toggle
local triggerbotKey = "LeftAlt"
local triggerbotKeyHeld = false
local triggerbotDebounce = false
local triggerbotDebounceTime = 0.05
local triggerbotThreshold = 12
local triggerbotReactionTimeMs = 0

-- Helper: Convert TokyoLib key string to UserInputType/KeyCode
local function getInputTypeFromBind(bind)
    if bind == "MB1" then return Enum.UserInputType.MouseButton1, true end
    if bind == "MB2" then return Enum.UserInputType.MouseButton2, true end
    if bind == "MB3" then return Enum.UserInputType.MouseButton3, true end
    for _, key in pairs(Enum.KeyCode:GetEnumItems()) do
        if key.Name == bind then return key, false end
    end
    return nil, false
end

-- Aimbot settings
local aimbotEnabled = false
local aimbotSmoothing = 0 -- 0 = instant, 100 = very slow
local aimbotWallCheck = true
local aimbotKeyHeld = false -- No longer configurable, always MB2 (right mouse button)

AimbotSection:AddToggle({
    text = "Enable Aimbot",
    state = aimbotEnabled,
    flag = "AimbotEnabled",
    tooltip = "Hold right mouse button to lock cursor onto the closest ESP head.",
    callback = function(state)
        if type(state) == "boolean" then
            aimbotEnabled = state
        else
            warn("Invalid AimbotEnabled value:", state)
        end
    end
})

AimbotSection:AddSlider({
    text = "Aimbot Smoothing",
    flag = "AimbotSmoothing",
    min = 0, max = 100, increment = 1, value = aimbotSmoothing,
    tooltip = "Higher = more smoothing (slower), 0 = instant snap",
    callback = function(value)
        if typeof(value) ~= "number" then
            warn("Aimbot Smoothing must be a number, got:", typeof(value))
            return
        end
        aimbotSmoothing = math.clamp(value, 0, 100)
    end
})

AimbotSection:AddToggle({
    text = "Aimbot Wall Check",
    state = aimbotWallCheck,
    flag = "AimbotWallCheck",
    tooltip = "Don't aim through walls (uses chams occlusion logic)",
    callback = function(state)
        if type(state) == "boolean" then
            aimbotWallCheck = state
        else
            warn("Invalid AimbotWallCheck value:", state)
        end
    end
})


-- === TRIGGERBOT UI RESTORED ===
TriggerbotSection:AddToggle({
    text = "Enable Triggerbot",
    state = triggerbotEnabled,
    flag = "TriggerbotEnabled",
    tooltip = "Enable or disable triggerbot.",
    callback = function(state)
        if type(state) == "boolean" then
            triggerbotEnabled = state
        else
            warn("Invalid TriggerbotEnabled value:", state)
        end
    end
})

TriggerbotSection:AddToggle({
    text = "Triggerbot Wall Check",
    state = triggerbotWallCheck,
    flag = "TriggerbotWallCheck",
    tooltip = "Don't trigger through walls (uses chams occlusion logic)",
    callback = function(state)
        if type(state) == "boolean" then
            triggerbotWallCheck = state
        else
            warn("Invalid TriggerbotWallCheck value:", state)
        end
    end
})

TriggerbotSection:AddBind({
    enabled = true,
    text = "Triggerbot Key",
    tooltip = "Key to hold for triggerbot",
    mode = "hold",
    bind = "LeftAlt",
    flag = "TriggerbotKey",
    callback = function(state)
        triggerbotKeyHeld = state
    end,
    keycallback = function(key)
        triggerbotKey = key
    end
})

TriggerbotSection:AddSlider({
    text = "Triggerbot Threshold",
    flag = "TriggerbotThreshold",
    min = 3, max = 25, increment = 1, value = triggerbotThreshold,
    tooltip = "How close (in pixels) the crosshair must be to the head to shoot (higher = easier to trigger)",
    callback = function(value)
        if typeof(value) ~= "number" then
            warn("Triggerbot Threshold must be a number, got:", typeof(value))
            return
        end
        triggerbotThreshold = math.clamp(math.floor(value), 3, 25)
    end
})

TriggerbotSection:AddSlider({
    text = "Triggerbot Reaction Time (ms)",
    flag = "TriggerbotReactionTimeMs",
    min = 0, max = 1000, increment = 10, value = triggerbotReactionTimeMs,
    tooltip = "How long (in milliseconds, max 1s) to wait before left clicking when triggerbot activates.",
    callback = function(value)
        if typeof(value) ~= "number" then
            warn("Triggerbot Reaction Time must be a number, got:", typeof(value))
            return
        end
        triggerbotReactionTimeMs = math.clamp(math.floor(value), 0, 1000)
    end
})

-- Aimbot key is always right mouse button (MB2)
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        aimbotKeyHeld = true
    end
end)
UserInputService.InputEnded:Connect(function(input, processed)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        aimbotKeyHeld = false
    end
end)

local function getClosestESPHead(wallCheck)
    local closestPart = nil
    local closestDist = math.huge
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    for _, model in ipairs(Workspace:GetChildren()) do
        if isValidNPC(model) and isAlive(model) then
            local head = model:FindFirstChild(ESP_CONSTANTS.TARGET_HEAD_PART_NAME)
            if head and head:IsA("BasePart") then
                local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                if onScreen then
                    local skip = false
                    if wallCheck then
                        local origin = Camera.CFrame.Position
                        local direction = (head.Position - origin)
                        local rayParams = RaycastParams.new()
                        rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                        rayParams.FilterDescendantsInstances = {player.Character or nil}
                        rayParams.IgnoreWater = true
                        local result = Workspace:Raycast(origin, direction, rayParams)
                        if result and result.Instance and not head:IsDescendantOf(result.Instance.Parent or result.Instance) then
                            skip = true
                        end
                    end
                    if not skip then
                        local dist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closestPart = head
                        end
                    end
                end
            end
        end
    end
    return closestPart
end



RunService.RenderStepped:Connect(function()
    -- Only run aimbot/triggerbot if menu is NOT open
    if not library.open then
        -- === AIMBOT LOGIC ===
        if aimbotEnabled and aimbotKeyHeld and Camera then
            local target = getClosestESPHead(aimbotWallCheck)
            if target and typeof(target.Position) == "Vector3" then
                local screenPos, onScreen = Camera:WorldToViewportPoint(target.Position)
                if onScreen then
                    local mousePos = UserInputService:GetMouseLocation()
                    local relX = screenPos.X - mousePos.X
                    local relY = screenPos.Y - mousePos.Y

                    if aimbotSmoothing == 0 then
                        -- Instantly snap to center of head
                        if mousemoverel then
                            mousemoverel(relX, relY)
                        elseif mousemoveabs then
                            mousemoveabs(screenPos.X, screenPos.Y)
                        end
                    else
                        -- Smoothing: 0 = instant, 100 = very slow
                        local smoothing = math.clamp(aimbotSmoothing, 0, 100) / 100
                        local moveX = relX * (1 - smoothing)
                        local moveY = relY * (1 - smoothing)
                        if mousemoverel then
                            mousemoverel(moveX, moveY)
                        elseif mousemoveabs then
                            mousemoveabs(mousePos.X + moveX, mousePos.Y + moveY)
                        end
                    end
                end
            end
        end

        -- === TRIGGERBOT LOGIC (with wallcheck toggle) ===
        if triggerbotEnabled and triggerbotKeyHeld and Camera and not triggerbotDebounce then
            local target = getClosestESPHead(triggerbotWallCheck)
            if target and typeof(target.Position) == "Vector3" then
                local screenPos, onScreen = Camera:WorldToViewportPoint(target.Position)
                if onScreen then
                    local mousePos = UserInputService:GetMouseLocation()
                    local relX = screenPos.X - mousePos.X
                    local relY = screenPos.Y - mousePos.Y
                    local dist = math.sqrt(relX * relX + relY * relY)
                    if dist <= triggerbotThreshold then
                        triggerbotDebounce = true
                        -- Add reaction time before firing
                        if triggerbotReactionTimeMs > 0 then
                            task.wait(triggerbotReactionTimeMs / 1000)
                        end
                        -- Simulate mouse click
                        if mouse1press and mouse1release then
                            mouse1press()
                            task.wait(0.02)
                            mouse1release()
                        elseif mouse1click then
                            mouse1click()
                        end
                        -- Debounce reset
                        task.spawn(function()
                            task.wait(triggerbotDebounceTime)
                            triggerbotDebounce = false
                        end)
                    end
                end
            end
        end
    end
end)



print("Combined ESP Script with TokyoLib UI Loaded. Scan Interval:", TARGET_SCAN_INTERVAL)
task.spawn(scanForCombinedESPTargets)
