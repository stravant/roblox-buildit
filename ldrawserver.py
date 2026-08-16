#!/usr/bin/env python3
"""
LDraw file server for the BuildIt importer plugin.

Serves files from the ldraw/ directory over a WebSocket so the plugin can
resolve part references. Run it and leave it running while importing:

    python ldrawserver.py

Protocol (JSON messages):
    -> {"type": "readfile", "id": <n>, "path": "parts/3001.dat"}
    <- {"type": "file", "id": <n>, "found": true, "content": "..."}

Requires: pip install websockets
"""

import asyncio
import json
import os

import websockets
import websockets.asyncio.server

PORT = 38742
LDRAW_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ldraw")


def read_ldraw_file(rel_path: str) -> str | None:
    """Read a file from the ldraw directory, or None if missing/invalid."""
    rel_path = rel_path.replace("\\", "/").lstrip("/")
    full = os.path.normpath(os.path.join(LDRAW_DIR, rel_path))
    root = os.path.normpath(LDRAW_DIR)
    if not full.startswith(root + os.sep):
        return None
    if not os.path.isfile(full):
        return None
    with open(full, "rb") as f:
        return f.read().decode("utf-8", errors="replace")


async def handler(websocket: websockets.asyncio.server.ServerConnection):
    peer = websocket.remote_address
    print(f"Client connected: {peer}")
    try:
        async for raw_msg in websocket:
            try:
                msg = json.loads(raw_msg)
            except json.JSONDecodeError:
                continue
            if msg.get("type") != "readfile":
                continue
            content = read_ldraw_file(msg.get("path", ""))
            await websocket.send(json.dumps({
                "type": "file",
                "id": msg.get("id"),
                "found": content is not None,
                "content": content,
            }))
    except websockets.exceptions.ConnectionClosed:
        pass
    print(f"Client disconnected: {peer}")


async def main():
    async with websockets.asyncio.server.serve(handler, "localhost", PORT):
        print(f"Serving {LDRAW_DIR} on ws://localhost:{PORT}")
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
