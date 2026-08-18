--!strict

-- The representative test set: common bricks, Technic, minifig, hinge,
-- wheel, and steering/pneumatic parts for playing with the main
-- connector types (doors/windows, track systems, and other obscure
-- categories are importable but not worth the palette space). Standing
-- rule: any part number the user mentions gets added here.
return {
	"3001", -- Brick 2x4: stud + socket grids
	"3003", -- Brick 2x2
	"3005", -- Brick 1x1 (known gap: no underside sockets)
	"3020", -- Plate 2x4
	"3623", -- Plate 1x3: pin-derived sockets
	"3700", -- Technic Brick 1x2: peghole
	"3701", -- Technic Brick 1x4: 3 pegholes
	"3704", -- Technic Axle 2
	"32062", -- Technic Axle 2 Notched
	"2780", -- Technic Friction Pin
	"3647", -- Technic Gear 8 Tooth: axle hole
	"30374", -- Bar 4L
	"4085c", -- Plate 1x1 with Clip Vertical
	"3957a", -- Antenna 4H: bar + tube base
	"3184", -- Plate 1x4 with Towball
	"2736", -- Technic Axle Towball
	"3170", -- Plate 1x2 with Ball Joint-8 on Both Ends
	"14418", -- Plate 1x2 with Socket Joint-8
	"6553", -- Axle hub: through axle hole perpendicular to a 1.5 axle
	"3651", -- Pin/bush connector: blind axle hole + pin hole + 2 studs
	"3713", -- Technic Bush
	"2429", -- Hinge Plate 1x4 (imports the full 73983 composite assembly)
	"2712", -- Technic Rotor 3 Blade
	"4019", -- Technic Gear 16 Tooth
	"4143", -- Technic Gear 14 Tooth Bevel
	"3648a", -- Gear 24 Tooth with 3 axleholes + 4 pin holes
	"2739a", -- Technic Steering Link 6L: two towball sockets
	"6538a", -- Technic Axle Joiner: axle hole + slip surface
	"6539", -- Technic Transmission Driving Ring: slips onto 6538a
	"6573", -- Technic Differential: gear post bar in the cage
	"3069b", -- Tile 1x2: multi-cell underside pocket grip
	"3937", -- Hinge 1x2 (imports the 3937c01 composite)
	"3680", -- Turntable 2x2 (imports the 3680c01 composite)
	"3183a", -- Plate 1x4 with classic towball socket
	"973", -- Minifig torso: neck stud
	"3626b", -- Minifig head: neck pocket + top stud
	"3820", -- Minifig hand: bar grip
	"3815", -- Minifig hips+legs (imports the 3815c01 two-joint composite)
	"3624", -- Minifig police hat: tube grips the head stud
	"3730", -- Plate 2x2 with towball socket (tow hitch)
	"3779", -- Plate 2x4 with towball socket on top
	"2855", -- Technic Turntable Type 1 (virtual assembly composite)
	"4275a", -- Hinge Plate 1x2 with 3 Fingers (h2 primitive)
	"4276a", -- Hinge Plate 1x2 with 2 Fingers (h1 primitive)
	"2452", -- Hinge Plate 1x2 with 3 Fingers On Side
	"30364", -- Hinge Brick 1x2 Locking, single click finger
	"30365", -- Hinge Brick 1x2 Locking, dual click fork
	"44301", -- Hinge Plate 1x2 Locking, single click finger
	"44302", -- Hinge Plate 1x2 Locking, dual click fork
	"3641", -- Tyre 6/50x8 (fits rim 4624)
	"4624", -- Wheel Rim 6.4x8
	"11209", -- Tyre 10/32x14 (fits rim 11208)
	"11208", -- Wheel Rim 10x14 with Fake Bolts
	"3024", -- Plate 1x1: box pocket socket
	"4073", -- Plate 1x1 Round: base tube center grip
	"3062b", -- Brick 1x1 Round: hollow stud + base tube grip
	"3833", -- Construction Helmet: recessed grip tube (headgear rule)
	"4870", -- Plate 2x2 with 2 Wheel Pins
	"2926", -- Plate 1x4 with 2 Wheel Pins
	"30027b", -- Wheel Rim 8x8 notched hole (wpinhole)
	"3149d", -- Hinge Plate 2x5 (classic vehicle hinge composite)
	"3829", -- Car Steering Stand and Wheel (composite)
	"30640", -- Car Steering Wheel Holder 2x2 (composite)
	"2605", -- Shock absorber (Slider composite)
	"19478-f1", -- Pneumatic cylinder 2x11 (Slider composite)
	"127c01-f1", -- Classic pneumatic cylinder 2x2x5 (Slider)
	"127c02-f1", -- Classic pneumatic pump with spring (Slider)
	"19474-f1", -- Pneumatic valve with toggle lever (Hinge)
	"41475-f1", -- Technic Shock Absorber 9L (Slider)
	"41838", -- Technic Shock Absorber 6.5L Soft (Slider)
	"40918-f1", -- Technic Linear Actuator 12L (Slider)
	"3750", -- Winch 2x4x2 with drum (virtual composite)
	-- Classic studded Technic: bricks with holes
	"32000", -- Technic Brick 1x2 with Holes
	"3894", -- Technic Brick 1x6 with Holes
	"3702", -- Technic Brick 1x8 with Holes
	"2730", -- Technic Brick 1x10 with Holes
	"3895", -- Technic Brick 1x12 with Holes
	"3703", -- Technic Brick 1x16 with Holes
	-- Classic studded Technic: plates with holes
	"3709b", -- Technic Plate 2x4 with Holes
	"32001", -- Technic Plate 2x6 with Holes
	"3738", -- Technic Plate 2x8 with Holes
	-- Classic studded Technic: gears
	"3649", -- Technic Gear 40 Tooth
	"3648b", -- Technic Gear 24 Tooth with Single Axle Hole
	"3650a", -- Technic Gear 24 Tooth Crown Type 1
	"6542a", -- Technic Gear 16 Tooth Clutch
	"4716", -- Technic Worm Gear 2L
	"3743", -- Technic Gear Rack 1x4
	-- Classic studded Technic: axles
	"4519", -- Technic Axle 3
	"3705", -- Technic Axle 4
	"32073", -- Technic Axle 5
	"3706", -- Technic Axle 6
	"3707", -- Technic Axle 8
	"3737", -- Technic Axle 10
	"3708", -- Technic Axle 12
	-- Classic studded Technic: pins and bushes
	"3673", -- Technic Pin (frictionless)
	"4274", -- Technic Pin 1/2
	"3749", -- Technic Axle Pin
	"6558", -- Technic Pin Long with Friction and Slot
	"32054", -- Technic Pin Long with Stop Bush
	"32123a", -- Technic Bush 1/2 Smooth
}
