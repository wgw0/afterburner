--!strict
-- The menu look (DEVELOPMENT.md §24.1): dark navy panels, afterburner orange accents, HUD green for
-- good news. One place for colours, fonts and sizes so every screen matches.

return table.freeze({
	Background = Color3.fromRGB(8, 14, 28),
	Panel = Color3.fromRGB(16, 27, 50),
	PanelLight = Color3.fromRGB(28, 42, 70),
	Stroke = Color3.fromRGB(52, 70, 104),
	Accent = Color3.fromRGB(255, 138, 61),
	AccentDark = Color3.fromRGB(190, 92, 34),
	Good = Color3.fromRGB(110, 255, 150),
	Bad = Color3.fromRGB(255, 95, 80),
	Warn = Color3.fromRGB(255, 196, 90),
	Text = Color3.fromRGB(240, 244, 250),
	Dim = Color3.fromRGB(150, 162, 186),
	Locked = Color3.fromRGB(90, 100, 120),

	Font = Enum.Font.Gotham,
	FontBold = Enum.Font.GothamBold,
	FontHeavy = Enum.Font.GothamBlack,
	FontMono = Enum.Font.RobotoMono,

	Radius = 8,
	Gap = 10,
	TopBar = 56,
})
