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
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 280, 180, 240, 140)
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

type Controller = { stop: () -> () }
local mBuildController: Controller? = nil

local function stopBuildTool()
	if mBuildController ~= nil then
		(mBuildController :: Controller).stop()
		mBuildController = nil
	end
	buildWidget.Enabled = false
	buildButton:SetActive(false)
end

buildButton.Click:Connect(function()
	if mBuildController ~= nil then
		stopBuildTool()
		plugin:Deactivate()
		return
	end
	-- Take mouse ownership so viewport clicks drive the tool instead of
	-- Studio selection.
	plugin:Activate(true)
	buildWidget.Enabled = true
	buildButton:SetActive(true)
	local BuildController = require(script.Parent.Src.shared.Building.BuildController)
	mBuildController = BuildController.start({
		guiParent = buildWidget,
		plugin = plugin,
	})
end)

-- Fires when the user activates another tool (or we Deactivate ourselves).
plugin.Deactivation:Connect(stopBuildTool)
