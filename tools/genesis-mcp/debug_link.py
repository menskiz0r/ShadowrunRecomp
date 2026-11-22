from __future__ import annotations

import json
import os
import socket
from dataclasses import dataclass
from typing import IO, Any

DEFAULT_HOST: str = "127.0.0.1"
DEFAULT_DEBUG_PORT: int = 4378
REQUEST_TIMEOUT_SECONDS: float = 5.0


@dataclass(frozen=True)
class DebugEndpoint:
    host: str
    port: int

    @classmethod
    def from_environment(cls) -> "DebugEndpoint":
        host = os.environ.get("GENESIS_DEBUG_HOST", DEFAULT_HOST)
        port_text = os.environ.get("GENESIS_DEBUG_PORT", str(DEFAULT_DEBUG_PORT))
        try:
            port = int(port_text)
        except ValueError as error:
            raise ValueError(f"GENESIS_DEBUG_PORT must be an integer, got {port_text!r}") from error
        return cls(host=host, port=port)

    def describe(self) -> str:
        return f"{self.host}:{self.port}"


class GenesisDebugLink:
    def __init__(self, endpoint: DebugEndpoint, timeout: float = REQUEST_TIMEOUT_SECONDS) -> None:
        self._endpoint = endpoint
        self._timeout = timeout
        self._connection: socket.socket | None = None
        self._reader: IO[bytes] | None = None
        self._next_request_id = 1

    def __enter__(self) -> "GenesisDebugLink":
        try:
            self._connection = socket.create_connection(
                (self._endpoint.host, self._endpoint.port), timeout=self._timeout
            )
        except OSError as error:
            raise RuntimeError(
                f"cannot reach the runner debug server at {self._endpoint.describe()}: {error}. "
                "Start the game with a debug.ini next to the executable so the server listens."
            ) from error
        self._connection.settimeout(self._timeout)
        self._reader = self._connection.makefile("rb")
        return self

    def __exit__(self, exception_type: object, exception_value: object, traceback: object) -> None:
        self._close()

    def _close(self) -> None:
        if self._reader is not None:
            self._reader.close()
            self._reader = None
        if self._connection is not None:
            self._connection.close()
            self._connection = None

    def request(self, command: dict[str, Any]) -> dict[str, Any]:
        connection = self._require_connection()
        reader = self._require_reader()
        request_id = self._next_request_id
        self._next_request_id += 1
        payload = dict(command)
        payload["id"] = request_id
        connection.sendall((json.dumps(payload) + "\n").encode("utf-8"))
        while True:
            line = self._read_line(reader)
            response = json.loads(line)
            if response.get("id") != request_id:
                continue
            if not response.get("ok", False):
                raise RuntimeError(f"the game rejected {command.get('cmd')}: {response.get('error', 'unknown error')}")
            return response

    def _read_line(self, reader: IO[bytes]) -> bytes:
        try:
            line = reader.readline()
        except socket.timeout as error:
            raise RuntimeError(
                f"no answer from the debug server at {self._endpoint.describe()} within {self._timeout} s; "
                "is the game paused or sitting on a loading screen?"
            ) from error
        except OSError as error:
            raise RuntimeError(f"debug server at {self._endpoint.describe()} dropped the connection: {error}") from error
        if not line:
            raise RuntimeError(f"debug server at {self._endpoint.describe()} closed the connection")
        return line

    def _require_connection(self) -> socket.socket:
        if self._connection is None:
            raise RuntimeError("debug link is not connected")
        return self._connection

    def _require_reader(self) -> IO[bytes]:
        if self._reader is None:
            raise RuntimeError("debug link is not connected")
        return self._reader

    def hold(self, mask: int) -> None:
        self.request({"cmd": "set_input", "keys": f"{mask:02X}"})

    def release(self) -> None:
        self.request({"cmd": "set_input", "keys": "off"})

    def current_frame(self) -> int:
        return int(self.request({"cmd": "frame_info"})["current_frame"])
