--!strict

-- Importer plugin entry: creates the toolbar + widgets synchronously, then
-- lazy-loads the tools on first use.

local toolbar = plugin:CreateToolbar("BuildIt")

--------------------------------------------------------------------------------
-- Import tool
--------------------------------------------------------------------------------

local importButton = toolbar:CreateButton(
	"BuildItImport",
	"Import LDraw parts with connection annotations",
	"",
	"Import Parts"
)

local importWidget = plugin:CreateDockWidgetPluginGui(
	"BuildItImporter",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 280, 250, 240, 210)
)
importWidget.Title = "BuildIt Importer"
importWidget.Name = "BuildItImporter"

local mImporterLoaded = false

local function ensureImporterLoaded()
	if mImporterLoaded then
		return
	end
	mImporterLoaded = true
	require(script.Parent.Src.importer.main)(importWidget)
end

importButton.Click:Connect(function()
	importWidget.Enabled = not importWidget.Enabled
	if importWidget.Enabled then
		ensureImporterLoaded()
	end
end)

importWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
	importButton:SetActive(importWidget.Enabled)
	if importWidget.Enabled then
		ensureImporterLoaded()
	end
end)

-- Studio restores widget enabled-state across sessions: populate now if
-- the panel starts open.
if importWidget.Enabled then
	ensureImporterLoaded()
end

--------------------------------------------------------------------------------
-- Build tool (Edit-mode part dragging/connecting, same controller as the
-- in-game tool)
--------------------------------------------------------------------------------

local buildButton = toolbar:CreateButton(
	"BuildItBuild",
	"Drag and connect imported parts in Edit mode",
	"",
	"Build"
)

local buildWidget = plugin:CreateDockWidgetPluginGui(
	"BuildItBuild",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 200, 400, 180, 300)
)
buildWidget.Title = "BuildIt Build"
buildWidget.Name = "BuildItBuild"

-- The palette lives in the widget PERMANENTLY (created on first open) so
-- the panel layout survives tool activation/deactivation; the Build
-- button only toggles mouse ownership. Clicking a palette entry
-- auto-activates the tool.
type Controller = { stop: () -> (), dragTemplate: (BasePart) -> () }
type Palette = { frame: Frame, destroy: () -> (), containsPoint: (Vector2) -> boolean }
local mBuildController: Controller? = nil
local mBuildPalette: Palette? = nil

local function stopBuildTool()
	if mBuildController ~= nil then
		(mBuildController :: Controller).stop()
		mBuildController = nil
	end
	buildButton:SetActive(false)
	-- Widget stays open.
end

local function startBuildTool()
	if mBuildController ~= nil then
		return
	end
	-- Take mouse ownership so viewport clicks drive the tool instead of
	-- Studio selection.
	plugin:Activate(true)
	buildButton:SetActive(true)
	local BuildController = require(script.Parent.Src.shared.Building.BuildController)
	mBuildController = BuildController.start({
		guiParent = buildWidget,
		plugin = plugin,
		palette = mBuildPalette,
	})
end

local function ensureBuildPalette()
	if mBuildPalette ~= nil then
		return
	end
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local templatesFolder = ReplicatedStorage:FindFirstChild("PartLibrary")
	if templatesFolder == nil then
		local folder = Instance.new("Folder")
		folder.Name = "PartLibrary"
		folder.Parent = ReplicatedStorage
		templatesFolder = folder
	end
	local PartPalette = require(script.Parent.Src.shared.Building.PartPalette)
	mBuildPalette = PartPalette.create(buildWidget, templatesFolder :: Folder, function(template: BasePart)
		startBuildTool()
		if mBuildController ~= nil then
			(mBuildController :: Controller).dragTemplate(template)
		end
	end)
end

--------------------------------------------------------------------------------
-- Rotate tool (click-drag a composite segment to hinge it)
--------------------------------------------------------------------------------

local rotateButton = toolbar:CreateButton(
	"BuildItRotate",
	"Click and hold a composite part's segment, drag to rotate its joint",
	"",
	"Rotate"
)

type RotateControllerHandle = { stop: () -> () }
local mRotateController: RotateControllerHandle? = nil

local function stopRotateTool()
	if mRotateController ~= nil then
		(mRotateController :: RotateControllerHandle).stop()
		mRotateController = nil
	end
	rotateButton:SetActive(false)
end

rotateButton.Click:Connect(function()
	if mRotateController ~= nil then
		stopRotateTool()
		plugin:Deactivate()
		return
	end
	stopBuildTool()
	plugin:Activate(true)
	rotateButton:SetActive(true)
	local RotateController = require(script.Parent.Src.shared.Building.RotateController)
	mRotateController = RotateController.start({ plugin = plugin })
end)

buildButton.Click:Connect(function()
	if mBuildController ~= nil then
		stopBuildTool()
		plugin:Deactivate()
		return
	end
	stopRotateTool()
	buildWidget.Enabled = true
	ensureBuildPalette()
	startBuildTool()
end)

-- Repopulate if the user opens the panel from Studio's view menus without
-- activating the tool.
buildWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
	if buildWidget.Enabled then
		ensureBuildPalette()
	end
end)

-- Fires when the user activates another tool (or we Deactivate ourselves).
plugin.Deactivation:Connect(function()
	stopBuildTool()
	stopRotateTool()
end)

-- Studio restores widget enabled-state across sessions: populate now if
-- the panel is already open.
if buildWidget.Enabled then
	ensureBuildPalette()
end
