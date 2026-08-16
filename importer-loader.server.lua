--!strict

-- Importer plugin entry: creates the toolbar + widget synchronously, then
-- lazy-loads main on first use.

local toolbar = plugin:CreateToolbar("BuildIt")
local button = toolbar:CreateButton(
	"BuildItImport",
	"Import LDraw parts with connection annotations",
	"",
	"Import Parts"
)

local widget = plugin:CreateDockWidgetPluginGui(
	"BuildItImporter",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 280, 180, 240, 140)
)
widget.Title = "BuildIt Importer"
widget.Name = "BuildItImporter"

local mLoaded = false

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	if widget.Enabled and not mLoaded then
		mLoaded = true
		require(script.Parent.Src.importer.main)(widget)
	end
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
end)
