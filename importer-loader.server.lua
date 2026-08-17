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

importButton.Click:Connect(function()
	importWidget.Enabled = not importWidget.Enabled
	if importWidget.Enabled and not mImporterLoaded then
		mImporterLoaded = true
		require(script.Parent.Src.importer.main)(importWidget)
	end
end)

importWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
	importButton:SetActive(importWidget.Enabled)
end)

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

buildButton.Click:Connect(function()
	if mBuildController ~= nil then
		stopBuildTool()
		plugin:Deactivate()
		return
	end
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
plugin.Deactivation:Connect(stopBuildTool)

-- Studio restores widget enabled-state across sessions: populate now if
-- the panel is already open.
if buildWidget.Enabled then
	ensureBuildPalette()
end
