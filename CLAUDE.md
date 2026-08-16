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
- `findConnections.lua` — discovers connector primitives by name during
  recursion: `stud*` = male stud, `stud3*` = underside pin, `stud4*` =
  underside tube. Recursion handles stud groups (`stug*`) for free.
- `deriveSockets.lua` — derives stud-sized "anti-stud" cells from tubes
  (4 diagonal neighbors) and pins (2 neighbors; phantom candidates culled
  by mesh bounds).
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
- `findSnapPlacement.lua` — pure snap solver: mates Stud<->Socket pairs
  (anti-parallel directions) translating the ghost the least; reports all
  mated pairs for visualization. Rotation is caller-controlled (yaw only).
- `PartPalette.lua` — panel UI listing PartLibrary templates with
  ViewportFrame thumbnails.
- `BuildController.lua` — drag/ghost/marker/placement controller. Drag out
  of the palette, release to place (release over the panel cancels), R
  rotates 90 degrees, RMB cancels. Connector markers: studs green, sockets
  blue, mated pairs yellow. Placed parts go in `workspace.Assembly`.

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
- Connection annotations on imported MeshParts: Attachments (UpVector =
  direction) named `StudN`/`SocketN` with a `ConnectorType` attribute;
  part attributes `PartNumber`, `Description`, `LDrawFile`.

### Known v1 limitations

- Parts whose underside pocket has no tube/pin primitive get no sockets
  (e.g. 1x1 bricks/plates — their pocket is a bare cylinder). Needs
  geometric detection or a special-case table later.
- Studs are classified by name prefix; exotic stud primitives (Technic,
  Duplo) may need a curated table.
- No texture/pattern (printed parts) or flexible part support.
- buildEditableMesh welds all vertices by position, so normals smooth
  across sharp edges (soft shading gradient on brick sides). Fix: split
  vertices when the face angle exceeds a crease threshold.
