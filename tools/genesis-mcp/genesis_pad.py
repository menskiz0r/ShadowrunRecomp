from __future__ import annotations

from typing import Final

BUTTON_BITS: Final[dict[str, int]] = {
    "up": 0x01,
    "down": 0x02,
    "left": 0x04,
    "right": 0x08,
    "b": 0x10,
    "c": 0x20,
    "a": 0x40,
    "start": 0x80,
}

BUTTON_NAMES: Final[str] = ", ".join(BUTTON_BITS)


def normalize_button(button: str) -> str:
    normalized = button.strip().lower()
    if normalized not in BUTTON_BITS:
        raise ValueError(f"unknown button {button!r}; expected one of {BUTTON_NAMES}")
    return normalized


def button_mask(button: str) -> int:
    return BUTTON_BITS[normalize_button(button)]
