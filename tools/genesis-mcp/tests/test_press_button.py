from __future__ import annotations

import asyncio
import json
import os
import socket
import sys
import threading
import time
import unittest

TOOL_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if TOOL_ROOT not in sys.path:
    sys.path.insert(0, TOOL_ROOT)

import server
from debug_link import DebugEndpoint, GenesisDebugLink
from genesis_pad import button_mask, normalize_button


class FakeDebugServer:
    def __init__(self) -> None:
        self._listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._listener.bind(("127.0.0.1", 0))
        self._listener.listen(1)
        self.port = self._listener.getsockname()[1]
        self.commands: list[dict[str, object]] = []
        self.frame = 100
        self._thread = threading.Thread(target=self._serve, daemon=True)
        self._thread.start()

    def _serve(self) -> None:
        connection, _ = self._listener.accept()
        with connection:
            reader = connection.makefile("rb")
            for line in reader:
                command = json.loads(line)
                self.commands.append(command)
                response: dict[str, object] = {"id": command["id"], "ok": True}
                if command["cmd"] == "frame_info":
                    response["current_frame"] = self.frame
                connection.sendall((json.dumps(response) + "\n").encode("utf-8"))
        self._listener.close()

    def input_commands(self) -> list[dict[str, object]]:
        return [command for command in self.commands if command["cmd"] == "set_input"]


class ButtonTableTest(unittest.TestCase):
    def test_button_names_are_case_insensitive(self) -> None:
        self.assertEqual(button_mask("A"), 0x40)
        self.assertEqual(button_mask(" start "), 0x80)
        self.assertEqual(normalize_button("Down"), "down")

    def test_unknown_button_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            button_mask("jump")


class LinkTest(unittest.TestCase):
    def test_unreachable_server_reports_the_endpoint(self) -> None:
        closed_port = self._closed_port()
        endpoint = DebugEndpoint(host="127.0.0.1", port=closed_port)
        with self.assertRaises(RuntimeError) as raised:
            with GenesisDebugLink(endpoint):
                pass
        self.assertIn(f"127.0.0.1:{closed_port}", str(raised.exception))

    @staticmethod
    def _closed_port() -> int:
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
        probe.close()
        return port


class PressButtonTest(unittest.TestCase):
    def setUp(self) -> None:
        self.fake_server = FakeDebugServer()
        os.environ["GENESIS_DEBUG_PORT"] = str(self.fake_server.port)

    def tearDown(self) -> None:
        os.environ.pop("GENESIS_DEBUG_PORT", None)

    def test_press_holds_then_releases(self) -> None:
        started = time.monotonic()
        message = server.press_button("a", 80)
        elapsed_ms = (time.monotonic() - started) * 1000.0
        commands = self.fake_server.input_commands()
        self.assertGreaterEqual(elapsed_ms, 75.0)
        self.assertEqual([command["keys"] for command in commands], ["40", "off"])
        self.assertIn("Pressed A for 80 ms", message)

    def test_read_state_is_a_placeholder(self) -> None:
        self.assertEqual(server.read_state(), "State will be here")

    def test_duration_is_bounded(self) -> None:
        with self.assertRaises(ValueError):
            server.press_button("a", 0)
        with self.assertRaises(ValueError):
            server.press_button("a", 60_001)


class ToolRegistrationTest(unittest.TestCase):
    def test_both_tools_are_exposed(self) -> None:
        tools = asyncio.run(server.server.list_tools())
        self.assertEqual({tool.name for tool in tools}, {"press_button", "read_state"})


if __name__ == "__main__":
    unittest.main()
