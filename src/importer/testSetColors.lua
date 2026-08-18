--!strict

-- Typical real-world colors for test-set parts, applied at import so
-- the test set reads at a glance instead of all-grey. Keyed by part
-- number; parts without an entry keep the default material color.

local kRed = Color3.fromRGB(196, 40, 28)
local kBlue = Color3.fromRGB(13, 105, 172)
local kYellow = Color3.fromRGB(245, 205, 48)
local kGreen = Color3.fromRGB(40, 127, 71)
local kWhite = Color3.fromRGB(242, 243, 243)
local kBlack = Color3.fromRGB(27, 42, 53)
local kLightGrey = Color3.fromRGB(163, 162, 165)
local kDarkGrey = Color3.fromRGB(99, 95, 98)
local kBrown = Color3.fromRGB(105, 64, 40)
local kOrange = Color3.fromRGB(218, 133, 65)
local kTan = Color3.fromRGB(204, 185, 141)
local kLavender = Color3.fromRGB(199, 173, 206)
local kSkin = Color3.fromRGB(245, 205, 48) -- classic yellow minifig skin

return {
	-- Bricks and plates
	["3001"] = kRed,
	["3003"] = kBlue,
	["3005"] = kYellow,
	["3020"] = kGreen,
	["3623"] = kWhite,
	["3024"] = kRed,
	["3069b"] = kWhite,
	["4073"] = kYellow,
	["3062b"] = kBlue,
	["3170"] = kRed,
	["14418"] = kLightGrey,
	["30374"] = kLightGrey,
	["3957a"] = kBlue,
	["3184"] = kRed,
	["2736"] = kBlack,
	["4085c"] = kWhite,
	-- Technic
	["3700"] = kLightGrey,
	["3701"] = kLightGrey,
	["3704"] = kRed, -- classic 2L axle
	["32062"] = kRed,
	["2780"] = kBlack,
	["3647"] = kLightGrey,
	["3651"] = kLightGrey,
	["3713"] = kLightGrey,
	["6553"] = kBlack,
	["2712"] = kLightGrey,
	["4019"] = kLightGrey,
	["4143"] = kTan,
	["3648a"] = kLightGrey,
	["2739a"] = kBlack,
	["6538a"] = kRed,
	["6539"] = kDarkGrey,
	["6573"] = kLightGrey,
	["27940"] = kBlack,
	-- Classic studded Technic
	["32000"] = kBlue,
	["3894"] = kRed,
	["3702"] = kYellow,
	["2730"] = kBlack,
	["3895"] = kWhite,
	["3703"] = kBlue,
	["3709b"] = kLightGrey,
	["32001"] = kDarkGrey,
	["3738"] = kLightGrey,
	["3649"] = kLightGrey,
	["3648b"] = kLightGrey,
	["3650a"] = kLightGrey,
	["6542a"] = kWhite, -- clutch gear
	["4716"] = kBlack,
	["3743"] = kLightGrey,
	["4519"] = kLightGrey,
	["3705"] = kBlack,
	["32073"] = kLightGrey,
	["3706"] = kBlack,
	["3707"] = kBlack,
	["3737"] = kBlack,
	["3708"] = kBlack,
	["3673"] = kLightGrey,
	["4274"] = kLightGrey,
	["3749"] = kTan,
	["6558"] = kBlue,
	["32054"] = kBlack,
	["32123a"] = kLightGrey,
	-- Hinges / turntables / articulation
	["2429"] = kLightGrey,
	["3937"] = kLightGrey,
	["3680"] = kLightGrey,
	["2855"] = kBlack,
	["4275a"] = kLightGrey,
	["4276a"] = kLightGrey,
	["2452"] = kLightGrey,
	["30364"] = kDarkGrey,
	["30365"] = kDarkGrey,
	["44301"] = kDarkGrey,
	["44302"] = kDarkGrey,
	["3149d"] = kLightGrey,
	-- Towballs / steering / suspension
	["3183a"] = kLightGrey,
	["3730"] = kLightGrey,
	["3779"] = kLightGrey,
	["3491"] = kLightGrey,
	["3829"] = kLightGrey,
	["30640"] = kBlack,
	["2605"] = kLightGrey,
	["41475-f1"] = kDarkGrey,
	["41838"] = kDarkGrey,
	["40918-f1"] = kLightGrey,
	["43097-f1"] = kLightGrey,
	["127c01-f1"] = kYellow, -- classic pneumatic yellow
	["127c02-f1"] = kYellow,
	["19474-f1"] = kBlue,
	["19478-f1"] = kLightGrey,
	-- Minifig / minidoll
	["973"] = kRed,
	["3626b"] = kSkin,
	["3820"] = kSkin,
	["3815"] = kBlue,
	["3624"] = kBlue,
	["3833"] = kYellow,
	-- Wheels / tyres
	["3641"] = kBlack,
	["4624"] = kLightGrey,
	["11209"] = kBlack,
	["11208"] = kLightGrey,
	["4870"] = kBlack,
	["2926"] = kBlack,
	["30027b"] = kLightGrey,
	-- Misc
	["3750"] = kLightGrey,
} :: { [string]: Color3 }
