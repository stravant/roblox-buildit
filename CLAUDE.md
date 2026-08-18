# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BuildIt is a LEGO building game for Roblox (early development). The current
foundation is a Lua library for working with LDraw part library data:
parsing, mesh flattening, and automatic connection-point discovery, plus an
importer plugin that turns LDraw parts into annotated MeshParts.

The LDraw part library lives in `ldraw/` (unpacked official library,
gitignored — parts/, p/ primitives, LDConfig.ldr). It is read from disk by
the Python side (runtests.py / ldrawserver.py) and served to Lua over a
WebSocket; the Lua library itself is pure and takes an abstract
`FileProvider` function.

## Projects / Build / Test

- `default.project.json` — The game place, served into the "BuildIt" place.
  **Uses port 34873** (`rojo serve` — non-default port, the default port is
  used by other workspace projects). Maps `src/shared` to
  `ReplicatedStorage.BuildIt`.
- `importer.project.json` — The importer plugin:
  `rojo build importer.project.json -p BuildItImporter.rbxmx`. Requires
  `python ldrawserver.py` running (ws://localhost:38742) to access LDraw
  data. Toolbar "BuildIt" > "Import Parts" opens a dock widget.
- `runtests.project.json` — Test runner plugin (same name/port convention as
  the other workspace projects — ws port 38741, only one project's test
  plugin active at a time). Run with `python runtests.py [filter]` with the
  runtests place open in Studio. The test protocol additionally supports
  `readfile` requests: specs can read real LDraw files via `t.readFile`
  (path relative to `ldraw/`, e.g. `"parts/3001.dat"`).

Entry scripts (`importer-loader.server.lua`, `runtests.server.lua`) live in
the repo root, NOT under `src/`, because Script instances in a .rbxmx plugin
execute in every open place — `src/` must contain only ModuleScripts (see
roblox-nightfall's CLAUDE.md for the war story).

## Part database / survey tooling

- `part_index.tsv` — prebuilt index of all 24k+ parts (regenerate with
  `python scripts/build_part_index.py`). Columns: id, !LDRAW_ORG type,
  description, moved-to target, keywords (includes BrickLink alternate
  ids), referenced subfile basenames, approx bbox size. ALWAYS grep this
  instead of scanning `ldraw/parts/*.dat` (globbing 22k files times out):
  `grep -iE "\tDoor" part_index.tsv`, `grep bump5000 part_index.tsv`
  (which parts use a primitive), `grep -i x547 part_index.tsv`
  (BrickLink id lookup).
- `scripts/probe_part.py <id> [name-filter]` — dump a part's top-level
  subfile references grouped by primitive with origins and rotation rows
  (for working out connector positions).

## Architecture

`src/shared/LDraw/` — the LDraw library (pure, provider-based):

- `Types.lua` — shared types (ParsedFile, FlatMesh, Connection, Socket, ...).
- `parseLDrawFile.lua` — parses one .dat/.ldr file. Normalizes filenames
  (lowercase, forward slashes) and winding (all certified geometry is stored
  CCW; mid-file BFC CW/CCW statements are consumed at parse time).
- `LDrawLibrary.lua` — resolution + caching over a FileProvider. Reference
  search order: `p/`, `parts/`, `models/` (so `s\3001s01.dat` resolves to
  `parts/s/3001s01.dat`, `48\4-4cyli.dat` to `p/48/4-4cyli.dat`).
- `flattenMesh.lua` — recursively flattens the composition tree into a
  triangle soup in root-part space. Winding flips (mirror transforms XOR
  BFC INVERTNEXT) are applied at emit; non-certified geometry is emitted
  double-sided.
- `connectorPrimitives.lua` — the curated connector primitive table
  (exact names + geometry conventions). Primitive names are traps
  (`axlehole` = hole, `axlehol8` = shaft, `axlehol2` = edge lines only);
  see PARTS_INDEX.md for representative parts and survey commands.
- `findConnections.lua` — discovers connectors during recursion via
  connectorPrimitives: stud families (prefix-safe), `peghole*` mouths
  (opposed pairs merged into through-holes with depth), `axlehole`-family
  and axle-shaft unit segments (colinear/notched segments merged),
  `connect*`/`confric*` Technic pin halves, `clip1`/`clip2` vertical
  clips, and radius-4 cylinders as Bars (geometric rule). Axial
  connectors carry center + axis + length; direction sign is arbitrary
  for them.
- `deriveSockets.lua` — derives stud-sized "anti-stud" cells from tubes
  (4 diagonal neighbors) and pins (2 neighbors; phantom candidates culled
  by mesh bounds).
- `coalesceRegions.lua` — merges connection cells into maximal rectangular
  grid regions (type + frame + dimension). Grouped by kind, snapped
  direction, plane, and lattice residual; greedy rectangle extraction;
  non-axis-aligned cells fall back to 1x1 regions. Extended connectors
  (bars, axles) will extend this model with a continuous length dimension.
- `LDrawColors.lua` — LDConfig.ldr !COLOUR parsing.
- `RobloxConvert.lua` — LDraw->Roblox space conversion. Two frame
  converters: `cframe()` maps semantic AXES (attachments), while
  `placementCFrame()` conjugates the rotation to map POINTS (placing
  model instances) — they differ and using the wrong one flips axes.
- `compositeParts.lua` — composite parts: assemblies of rigid segments
  that always drag as one unit but articulate (hinges). Curated per
  LDraw Shortcut assembly (joint position/axis); segment part ids
  redirect to the assembly. Imported by `importer/importComposite.lua`
  as a Model (attributes PartNumber/LDrawFile/JointType) of annotated
  segment MeshParts, each carrying a "JointPivot" Attachment (UpVector =
  articulation axis) for the future joint graph. The palette and build
  tool treat Models as single pivot-based units; segments still expose
  their own connectors.
- `loadModel.lua` — .mpd/.ldr model files (e.g. LDraw OMR sets in
  `sets/`, served under the `sets/` path prefix): splits `0 FILE`
  sections and flattens to part instances (ref + transform + color).
- `buildEditableMesh.lua` — FlatMesh -> welded EditableMesh (Studio only).

`src/importer/` — importer plugin modules: `main.lua` (widget UI),
`importPart.lua` (MeshPart + Attachment annotation), `importModel.lua`
(whole-set import: templates for every unique part + assembled colored
clones in a workspace folder; typing "8880" resolves `sets/8880-1.mpd`),
`wsFileProvider.lua` (FileProvider over WebSocket). Imports go into
`ReplicatedStorage.PartLibrary` (the build tool's palette source; the
folder survives rojo syncing since ReplicatedStorage ignores unknown
instances).

`src/shared/Building/` — the in-game build (test) tool:

- `getConnectors.lua` — reads connector Attachments off a part.
- `findSnapPlacement.lua` — pure snap solver; reports all mated pairs for
  visualization. Rotation is caller-controlled (yaw only). Point rule:
  Stud<->Socket coincide with anti-parallel directions. Axial rule
  (TechnicPin<->PegHole, Axle<->AxleHole, Axle<->PegHole, Bar<->Clip,
  Bar<->HollowStud, Bar<->BarHole): axes parallel (either sign), centered
  on the axis, sliding along it by up to half the length difference
  (equal lengths lock centered — how pins click in). OneSided female
  bores (hollow studs) use an asymmetric interval instead: bottomed-out
  flush to half-engaged. Ball rule (Towball<->TowballSocket): centers
  coincide, rotation free. Mouth rule (Stud<->PegHole): stud locks into
  the nearer hole mouth pointing inward. Candidates misaligned by up to
  60 degrees get a shortest-arc ALIGNMENT ROTATION of the whole dragged
  unit (bar into a minifig hand's tilted grip); beyond the cone they
  reject. Ranked by remaining degrees of freedom first (point/locked-
  axial = 0, ball = 0.5, sliding axial = 1), then score (distance +
  rotation penalty + grab bias).
- `mates.lua` — shared mating logic: the partner table, mate rules,
  and the engaged-pair check (are two world-placed connectors mated
  within epsilon?). Both findSnapPlacement (matched-pair reporting)
  and AssemblyGraph use it, so "connected" means one thing.
- `AssemblyGraph.lua` — the assembly connection graph over placed
  units (composite Models are single nodes; their internal joints
  stay out). Built with a spatial hash over world connectors (axial
  connectors inserted along their span), O(N x local density);
  incremental addUnit/removeUnit. Two queries:
  - partition(id, direction): the units that must move together when
    dragging `id` along `direction` — an edge releases only if EVERY
    mate on it separates that way (studs pull off along the stud
    axis, bars slide out axially, balls/magnets release any way).
    Lifting a mid-wall brick takes what's stacked above; dragging
    down takes what's below; sideways takes everything.
  - physicsPlan(): folds each edge's mates into a rigid-motion
    archetype (Fixed/Hinge/Cylindrical/Ball) via an intersection
    table (two offset pin lines -> Fixed; collinear -> Hinge; two
    separated towballs -> Hinge through both), absorbs fastener
    units (pins/axles/bars joining exactly two structural units)
    into virtual mates between the pair, then union-finds Fixed
    edges into weld clusters and emits constraints for the rest.
    2000-unit wall: build + partition + plan ~250ms.
- `applyPhysicsJoints.lua` — instantiates real Roblox joints for an
  assembly: WeldConstraints for graph physicsJoints() welds (nearest
  segment parts), Hinge/Cylindrical/Prismatic/BallSocket constraints
  for the articulated edges (fresh attachments with primary axis =
  joint axis), and composite JointPivot pairs as hinge/prismatic
  constraints. Returns the created folder, the weld part-pairs (for
  part-level rigid grouping), and destroy().
- `RotateController.lua` — Edit-mode Rotate tool (plugin "Rotate"
  toolbar button), PHYSICS-DRIVEN: click-hold any part of a placed
  assembly and drag. Rebuilds the AssemblyGraph from scratch, applies
  physics joints over the connected assembly, unanchors everything
  except the largest rigid part-group (excluding the grabbed one),
  then drives the grab point toward the cursor with an AlignPosition
  while stepping the sim manually (workspace:StepPhysics on just the
  sim parts, gravity zeroed, velocities damped per substep) — so a
  hinge swings, a 4-bar follows, a piston slides, and double-pinned
  liftarms stay rigid through the solver. Release commits the pose
  (one undo recording); RMB/Esc/Ctrl+Z cancels and restores.
- `PartPalette.lua` — panel UI listing PartLibrary templates with
  ViewportFrame thumbnails and a search box (name/part number
  substring).
- Instruction sets (in-game set building; flat square-corner UI via
  `FlatUI.lua`, entry menu in `src/entry/BuildTool.client.lua`):
  - `SetData.lua` — pure model: a set = name + flat ordered steps
    (`bag` markers, `subbuild` markers opening an isolated target,
    `place` steps with partNumber/color/pose relative to their target
    root, `attach` steps carrying the sub-build root pose in
    main-build space). JSON round-trip; bag ranges; active target.
  - `SetStore.lua` — sets persist as StringValues in
    workspace.BuildItSets.
  - `SetRig.lua` — materializer: container + main root Model +
    per-sub-build roots on platform slabs; buildTo(cursor) rebuilds
    for scrubbing; attach folds sub parts into the main root.
  - `SetGuide.lua` — pure follower logic: matching pending steps for
    a dragged part, nearest-target snap pick, next-step selection
    (attach waits for its range), bag completion.
  - `SetEditorController.lua` — the build tool (via BuildController's
    placeParent/scanRoot/onPicked/onPlaced hooks) recording steps at
    a cursor, with the `Sequencer.lua` strip on top: square cell per
    step, scrub-to-rebuild, +BAG/+SUB-BUILD/DELETE/SAVE. Dropping a
    whole open sub-build onto the main build (assembly move mode)
    records its attach step.
  - `SetPlayerController.lua` — guided following: the current bag's
    parts spawn as a pile on a tray; dragging a part near a pending
    matching step's pose snaps it in; accent hint ghost shows the
    next step; bags advance when drained; the completed sub-build
    drags onto the main build as a whole.
- `BuildController.lua` — drag/ghost/marker/placement controller. Drag out
  of the palette OR pick up any connector-annotated workspace part;
  release to place (release over the panel cancels), R yaws 90 degrees
  about world Y, T tips 90 degrees toward the camera (nearest cardinal
  axis at press time) — both WORLD-space steps premultiplied onto the
  accumulated orientation (composed on a picked part's existing
  rotation), RMB/Esc cancels (restores a picked part). Connector markers: studs green, sockets blue,
  mated pairs yellow. New parts go in `workspace.Assembly` in-game or
  workspace in Edit mode; picked parts keep their parent. Runs in two
  contexts: in-game via `src/entry/BuildTool.client.lua`, and in Edit mode
  via the plugin's "Build" toolbar button (`start({guiParent, plugin})` —
  palette in a dock widget, `plugin:Activate` owns the mouse; deactivation
  stops the tool). Edit-mode undo: each drag is ONE recording spanning
  pickup to place — committed on place, canceled-with-rollback on abort
  (aborted drags leave no undo entry); Ctrl+Z mid-drag cancels the drag
  first. IMPORTANT: picked-up units are HIDDEN in place (transparency +
  CanQuery off), never unparented — unparenting mid-recording breaks
  undo, and a plugin reload mid-drag would orphan the part forever.
  Performance: snapping/markers never scan the whole place — a
  per-frame GetPartBoundsInRadius query around the ghost picks candidate
  parts (lazy per-part connector cache, cleared per drag), and markers
  come from a bounded pool reassigned to whatever is in range.
  GROUP DRAGGING: a three-mode toggle (top of the build panel) decides
  what a pickup carries. "Part" = just the picked unit. "Chunk"
  (default) = units held by clutched joints — what sits on the picked
  unit's STUDS comes along and its SOCKETS always break from what's
  underneath (no drag-direction guessing), plus captive joints (pins,
  clips, hinges, balls, slides); loose fits (axle spinning in a round
  hole, bar through a bore) stay behind. "Assembly" = the whole
  connected component including loose fits. Picking up rebuilds the
  AssemblyGraph from scratch (undo/external edits make the workspace
  the only source of truth in Edit mode; ~250ms at 2000 units); the
  group lifts immediately: hidden in place, ghosted at fixed offsets
  from the primary, connectors contributing to snapping/markers.
  Placement moves all members rigidly and cancel restores them
  untouched, inside the same single undo recording. Test-set imports
  are tinted with typical real-world colors (testSetColors.lua).

`src/entry/BuildTool.client.lua` — StarterPlayerScripts bootstrap for the
build tool (mounted only by default.project.json, never the test plugin).

## LDraw facts (verified against the library)

- Units: 1 LDU = 0.4mm. Stud grid pitch 20 LDU, brick height 24, plate
  height 8, stud height 4. Default Roblox scale is 1/20 (1 grid module =
  1 stud), with (x,y,z) -> (x,-y,-z) (LDraw is right-handed with -Y up;
  the mapping is a 180-degree rotation, preserving winding).
- Part origin is at the TOP face (studs at y=0 extending to y=-4; a brick
  body spans y=0..24).
- `stud4`/`stud3` primitives span local y in [-4, 0] with the free rim at
  y=-4, and are placed with a negative Y scale so the rim lands on the
  part's bottom face. For both studs and tubes/pins, `direction` =
  normalized transformed -Y = "toward the mating part", and the mating
  plane point is the transform origin (studs) / transform*(0,-4,0)
  (tubes/pins).
- Edge sharpness is authored in the data: type 2 edge lines mark SHARP
  edges, type 5 conditional lines mark SMOOTH (curved) edges.
  buildEditableMesh uses these for normal generation, with a 40-degree
  crease-angle fallback for unmarked edges (e.g. across subfile seams).
- Connection annotations on imported MeshParts: one Attachment per REGION
  (e.g. `Studs4x2`), not per cell. Attributes `ConnectorType`
  ("Stud"/"Socket"), `CountX`, `CountZ`, `Pitch` (Roblox studs); CFrame at
  the region center with UpVector = mating direction and XVector/ZVector
  the grid axes. `Building/getConnectors.lua` expands regions to cells
  (attachments without counts read as 1x1, so legacy per-cell annotations
  still work). Parts are named from the LDraw description ("Brick 2 x 4");
  attributes `PartNumber` ("3001") and `LDrawFile` ("3001.dat"). Importing
  drops the template in PartLibrary (replacing any previous template with
  the same PartNumber) plus a selected copy in workspace in front of the
  camera.

### Connector taxonomy

~30 connection types across five mate rules (see PARTS_INDEX.md for the
part-by-part table, findSnapPlacement.lua for the rules):

- point (coincide + anti-parallel): Stud<->Socket, Magnet, TrackEnd,
  CoasterEnd, MonoEnd, MonoRampJoint (each rail system self-mates only
  with itself — incompatible systems never cross-snap).
- axial (parallel axes, slide by half the length difference; equal
  lengths lock): TechnicPin/PegHole, Axle/AxleHole, Bar vs
  Clip/HollowStud/BarHole/AxleHole, WheelPin/WheelHole(+BarHole),
  SlipAxle/SlipRing, HingePin/HingeSocket, HingeFinger, ClickFinger/
  ClickFork, ArmFinger, MinidollHinge, SlideRail/SlideGroove,
  TyreBore/RimSeat (also gated by a mating radius within 0.15 studs).
- ball: Towball<->TowballSocket. mouth: Stud<->PegHole.
- Composites (compositeParts.lua) carry articulation joints instead:
  hinge plates, turntables, minifig torso/hips assemblies.

Snap-level assembly of curated pairs is verified end to end by
src/shared/Building/snapPairs.spec.lua — add a row there when curating
a new pair.

### Known v1 limitations

- Studs are classified by name prefix; exotic stud primitives (Technic,
  Duplo) may need a curated table.
- No texture/pattern (printed parts) or flexible part support.
