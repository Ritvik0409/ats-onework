"""Password hashing — Argon2id via pwdlib (arch. doc §13, §48).

The rest of the application calls only ``hash_password`` / ``verify_password``
/ ``verify_and_update_password`` and never knows the algorithm — swapping
implementations touches this file alone. CPU-bound hashing is offloaded to a
worker thread so the asyncio event loop stays responsive (§48).
"""

from __future__ import annotations

from asyncio import to_thread

from pwdlib import PasswordHash

_hasher = PasswordHash.recommended()


async def hash_password(password: str) -> str:
    return await to_thread(_hasher.hash, password)


async def verify_password(password: str, password_hash: str) -> bool:
    return await to_thread(_hasher.verify, password, password_hash)


async def verify_and_update_password(
    password: str,
    password_hash: str,
) -> tuple[bool, str | None]:
    """Verify and, when the stored hash uses outdated parameters, return a
    re-hashed replacement — persist it on successful login (§13)."""
    return await to_thread(_hasher.verify_and_update, password, password_hash)
