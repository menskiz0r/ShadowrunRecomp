# genesis-mcp

An MCP server that drives the running ShadowrunRecomp window: it presses Sega
Genesis pad buttons, returns real screenshots, and will describe the screen in
text.

It talks to the runner's own debug command server (line-delimited JSON over TCP),
so no engine changes are needed.

## Tools

| Tool | Arguments | Result |
|---|---|---|
| `press_button` | `button` (`up`, `down`, `left`, `right`, `a`, `b`, `c`, `start`), `duration_ms` (default `150`) | Holds the button, waits, releases, returns the frame span |
| `screenshot` | none | The current screen as a PNG image (320x224) |
| `read_state` | none | `State will be here` (placeholder for the description) |

Button names are case-insensitive. `duration_ms` is bounded to 1..60000. The
release is sent in a `finally` block, so an interrupted call does not leave a
button stuck.

`screenshot` asks the runner for a PNG capture and returns those bytes as MCP
image content, so a client renders the real screen. The capture goes through
`TemporaryDirectory`, so nothing is left on disk. `read_state` is reserved for a
textual description and is still a placeholder.

## Setup

```powershell
python -m pip install -r tools\genesis-mcp\requirements.txt
```

Enable the runner's command server by creating `debug.ini` next to
`ShadowrunRecomp.exe` (the file's presence is what turns the server on):

```ini
port=4378
```

Then launch the game and press a button through an MCP client:

```powershell
build\ShadowrunRecomp.exe "game\shadowrun.bin"
```

## Client configuration

opencode (`opencode.json`):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "genesis-pad": {
      "type": "local",
      "command": ["python", "C:\\Users\\Ilia\\Sources\\ShadowrunRecomp-Extended\\tools\\genesis-mcp\\server.py"],
      "enabled": true
    }
  }
}
```

Any stdio MCP client works; the server writes only protocol messages to stdout.

## Endpoint override

| Variable | Default |
|---|---|
| `GENESIS_DEBUG_HOST` | `127.0.0.1` |
| `GENESIS_DEBUG_PORT` | `4378` |

The oracle build listens on `4379`, so set `GENESIS_DEBUG_PORT=4379` to drive it.

## Wire commands

`press_button` sends `set_input` with the Genesis bit mask and later releases it;
`screenshot` asks the runner to write the current framebuffer:

| Command | Meaning |
|---|---|
| `{"cmd":"frame_info"}` | current wall frame, used for the reported span |
| `{"cmd":"set_input","keys":"40"}` | hold A (`bit 6`) |
| `{"cmd":"set_input","keys":"off"}` | release the TCP input source |
| `{"cmd":"screenshot","path":"C:/…/screen.png"}` | write the current framebuffer |

Bits: `up` 0x01, `down` 0x02, `left` 0x04, `right` 0x08, `b` 0x10, `c` 0x20,
`a` 0x40, `start` 0x80. The runner merges this source with the live keyboard and
gamepad instead of replacing them.

Screenshot paths are sent with forward slashes: the runner's JSON reader copies
string values verbatim, so an escaped `\\` would arrive as a literal doubled
backslash and the write would fail.

Each tool call opens its own connection and closes it afterwards, because the
runner serves one client at a time.

## Tests

```powershell
python -m unittest discover -s tools\genesis-mcp\tests -v
```

The suite starts a fake command server, so it needs neither the game nor a ROM.
