--!strict

-- The representative test set from PARTS_INDEX.md: one part per handled
-- connection category, for playing with every connector type. Standing
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
	"6135", -- Palm trunk with axle hole
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
	"791", -- Window shutter 1x3x5: bump hinge pins
	"671", -- Door 1x6x10: full-height hinge rod
	"670", -- Door 1x6x10 Frame: hinge sockets both sides
	"3853", -- Window 1x4x3: bump hinge pins on the frame rails
	"3856", -- Window 1x2x3 Shutter: hook recesses for 3853's bumps
	"2657", -- Door 1x3x5: bump pins both ends
	"2656", -- Container Cupboard 2x3x5: corner hinge holes for 2657
	"42205", -- Door 1x6x6 Frame: shared hole-for-bump corner bosses
	"51239", -- Window 1x3x3 Frame: same hole-for-bump bosses
	"6798", -- Window 1x3x2 Frame: same hole-for-bump bosses
	"3644", -- Door 1x4x6 Grooved: segmented r2 hinge rod
	"30179", -- Door 1x4x6 Frame Type 1: corner pivot bores
	"2042", -- Container Cupboard 2x6x7: side-rail hinge stacks
	"2043", -- Container Cupboard 2x6x7 Door: outward end pins
	"60596", -- Door 1x4x6 Frame (newer mold): r2.5 corner bores
	"60623", -- Door 1x4x6 Stud Handle (newer mold): short end pins
	"4130", -- Door 2x4x5 Frame: r2 corner bores
	"4131", -- Door 2x4x5: capped hinge rod
	"4071", -- Door 2x6x7 Frame: corner rails + nubs
	"4072", -- Door 2x6x7 Four Panes: capped hinge rod
	"4275a", -- Hinge Plate 1x2 with 3 Fingers (h2 primitive)
	"4276a", -- Hinge Plate 1x2 with 2 Fingers (h1 primitive)
	"2452", -- Hinge Plate 1x2 with 3 Fingers On Side
	"30364", -- Hinge Brick 1x2 Locking, single click finger
	"30365", -- Hinge Brick 1x2 Locking, dual click fork
	"44301", -- Hinge Plate 1x2 Locking, single click finger
	"44302", -- Hinge Plate 1x2 Locking, dual click fork
	"412", -- Arm Piece with 2 and 3 Fingers Rotated
	"3612", -- Arm Piece with 2 and 3 Fingers Aligned
	"3641", -- Tyre 6/50x8 (fits rim 4624)
	"4624", -- Wheel Rim 6.4x8
	"11209", -- Tyre 10/32x14 (fits rim 11208)
	"11208", -- Wheel Rim 10x14 with Fake Bolts
	"2607bc01", -- Magnet Holder Technic Brick with magnet
	"2609bc01", -- Magnet Holder Tile with magnet
	"3024", -- Plate 1x1: box pocket socket
	"4073", -- Plate 1x1 Round: base tube center grip
	"3062b", -- Brick 1x1 Round: hollow stud + base tube grip
	"92198", -- Friends Head: neck bar hole + hair stud
	"1006030", -- Friends Girl Torso: neck bar + hip receivers
	"1015152", -- Friends Hips (thin hinge): curated D-posts
	"2645", -- Friends Hair: pin hole for the head stud
	"3833", -- Construction Helmet: recessed grip tube (headgear rule)
	"2440", -- Hinge 6x3 Radar: hand-built finger row
	"3314", -- Excavator Arm 2x6x2: tip finger row
	"3433", -- Excavator Bucket 5x3: hinge row
	"2347", -- Excavator Bucket 6x3: hinge row
	"2349a", -- Hinge Car Roof 4x4 Sunroof frame
	"2348a", -- Glass for sunroof: hinge edge
	"4870", -- Plate 2x2 with 2 Wheel Pins
	"2926", -- Plate 1x4 with 2 Wheel Pins
	"30027b", -- Wheel Rim 8x8 notched hole (wpinhole)
	"4532", -- Container Cupboard 2x3x2: drawer groove
	"4536", -- Container Cupboard Drawer: slide rail
	"850", -- Fire ladder bottom section: slide groove
	"852", -- Fire ladder top section: slide rail
	"851a", -- Fire ladder middle section: both slide interfaces
	"420", -- Classic 2x12 ladder bottom: slide groove
	"421", -- Classic 2x12 ladder top: slide rail
	"837", -- Homemaker Cupboard 4x4x4: corner hinge bores
	"838", -- Homemaker Cupboard Door: hinge rod
	"74746", -- Train Track 9V Straight: track ends
	"53401", -- Train Track RC Straight: track ends
	"74747", -- Train Track 9V Curved: R800 x 22.5 degree ends
	"53400", -- Train Track RC Curved: same arc
	"32087", -- Train Track 9V Crossing: four ends
	"25059", -- Roller Coaster Straight 4x16
	"26022", -- Roller Coaster Straight 4x8
	"25061", -- Roller Coaster Curve 90 R12
	"2670", -- Monorail Track Straight 4x8
	"2672", -- Monorail Track Curve Quarter (R560)
	"2677", -- Monorail Ramp Lower Section
	"2678", -- Monorail Ramp Upper Section
	"2861", -- Train Track 9V Switch Left: three ends
	"2859", -- Train Track 9V Switch Right: three ends
	"50945", -- =Tyre 6/30x11: alias-prefixed description gate
	"1023035", -- Friends Legs Cargo Pants (thin hinge knuckle)
	"1022657", -- Friends Legs Shorts (same shared hinge subpart)
	"25727", -- Friends Legs Cargo (thick hinge): foot pockets
	"15118", -- Ladder 2.6x16: rungs as bars
	"11299", -- Ladder 2.6x16 with Handrails: rungs as bars
	"4533", -- Container Cupboard 2x3x2 Door: hinge rod
	"4534", -- Container Cupboard 2x3x4: corner bores
	"4535", -- Container Cupboard 2x3x4 Door: hinge rod
	"795", -- Arm Piece with Disc and 2 Fingers
	"4221", -- Arm Piece Grab Jaw: single finger
	"4000", -- Ladder 4x15.6: semi-circular pivot bar
	"841", -- Homemaker Stove: oven door hinge grip
	"843", -- Homemaker Stove Door: fold-down rod
	"2", -- Container Drawers 4x4x4: two slots
	"3", -- Container Drawer 4x4x2: slide rail
	"745", -- Roadsign Base Round Type 1: knob neck
	"3350", -- Roadsign Round: clamp + stacking post
	"4207a", -- Ladder 2.6x14 with Stops: rungs as bars
}
