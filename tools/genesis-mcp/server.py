from __future__ import annotations

import tempfile
import time
from pathlib import Path
from typing import Final

from mcp.server.mcpserver import Image, MCPServer

from debug_link import DebugEndpoint, GenesisDebugLink
from genesis_pad import button_mask, normalize_button

DEFAULT_DURATION_MS: Final[int] = 150
MINIMUM_DURATION_MS: Final[int] = 1
MAXIMUM_DURATION_MS: Final[int] = 60_000
READ_STATE_PLACEHOLDER: Final[str] = "State will be here"

server = MCPServer(
    name="genesis-pad",
    title="Sega Genesis pad",
    instructions=(
        "Controls the running ShadowrunRecomp window through the runner's debug command server. "
        "Launch the game with a debug.ini next to ShadowrunRecomp.exe so the server listens on "
        "127.0.0.1:4378, or point GENESIS_DEBUG_HOST and GENESIS_DEBUG_PORT elsewhere."
    ),
)


def validate_duration(duration_ms: int) -> int:
    if duration_ms < MINIMUM_DURATION_MS or duration_ms > MAXIMUM_DURATION_MS:
        raise ValueError(
            f"duration_ms must be between {MINIMUM_DURATION_MS} and {MAXIMUM_DURATION_MS}, got {duration_ms}"
        )
    return duration_ms


def frame_or_none(link: GenesisDebugLink) -> int | None:
    try:
        return link.current_frame()
    except RuntimeError:
        return None


@server.tool(
    description=(
        "Hold one Sega Genesis pad button for a number of milliseconds and then release it. "
        "Buttons: up, down, left, right, a, b, c, start."
    )
)
def press_button(button: str, duration_ms: int = DEFAULT_DURATION_MS) -> str:
    mask = button_mask(button)
    duration = validate_duration(duration_ms)
    endpoint = DebugEndpoint.from_environment()
    with GenesisDebugLink(endpoint) as link:
        first_frame = frame_or_none(link)
        link.hold(mask)
        try:
            time.sleep(duration / 1000.0)
        finally:
            link.release()
        last_frame = frame_or_none(link)
    name = normalize_button(button).upper()
    if first_frame is None or last_frame is None:
        return f"Pressed {name} for {duration} ms."
    return f"Pressed {name} for {duration} ms across frames {first_frame}..{last_frame}."


@server.tool(description="Capture the current game screen and return it as a PNG image.")
def screenshot() -> Image:
    endpoint = DebugEndpoint.from_environment()
    with tempfile.TemporaryDirectory(prefix="genesis-mcp-") as directory:
        capture_path = Path(directory) / "screen.png"
        with GenesisDebugLink(endpoint) as link:
            link.screenshot(str(capture_path))
        if not capture_path.exists():
            raise RuntimeError("the runner answered the screenshot command but wrote no file")
        return Image(data=capture_path.read_bytes(), format="png")


@server.tool(description="Return a textual description of the current game screen.")
def read_state() -> str:
    return READ_STATE_PLACEHOLDER


def main() -> None:
    server.run()


if __name__ == "__main__":
    main()
