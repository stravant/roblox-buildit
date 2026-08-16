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
- `RobloxConvert.lua` — LDraw->Roblox space conversion.
- `buildEditableMesh.lua` — FlatMesh -> welded EditableMesh (Studio only).

`src/importer/` — importer plugin modules: `main.lua` (widget UI),
`importPart.lua` (MeshPart + Attachment annotation), `wsFileProvider.lua`
(FileProvider over WebSocket). Imports go into
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
  flush to half-engaged. Candidates are ranked by remaining degrees of
  freedom first (point/locked-axial = 0 beats sliding axial = 1),
  translation distance as tiebreaker.
- `PartPalette.lua` — panel UI listing PartLibrary templates with
  ViewportFrame thumbnails.
- `BuildController.lua` — drag/ghost/marker/placement controller. Drag out
  of the palette OR pick up any connector-annotated workspace part;
  release to place (release over the panel cancels), R yaws 90 degrees,
  T tilts 90 degrees about world X (both composed on a picked part's
  existing rotation), RMB/Esc cancels (restores a picked part). Connector markers: studs green, sockets blue,
  mated pairs yellow. New parts go in `workspace.Assembly` in-game or
  workspace in Edit mode; picked parts keep their parent. Runs in two
  contexts: in-game via `src/entry/BuildTool.client.lua`, and in Edit mode
  via the plugin's "Build" toolbar button (`start({guiParent, plugin})` —
  palette in a dock widget, placements wrapped in undo recordings,
  `plugin:Activate` owns the mouse; deactivation stops the tool).

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

### Known v1 limitations

- Parts whose underside pocket has no tube/pin primitive get no sockets
  (e.g. 1x1 bricks/plates — their pocket is a bare cylinder). Needs
  geometric detection or a special-case table later.
- Studs are classified by name prefix; exotic stud primitives (Technic,
  Duplo) may need a curated table.
- No texture/pattern (printed parts) or flexible part support.
