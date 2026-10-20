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


#: Passwords that are too common to be worth hashing and checking.
TOO_COMMON = frozenset(
    {
        "password",
        "password1",
        "password123",
        "12345678",
        "123456789",
        "1234567890",
        "qwerty123",
        "qwertyuiop",
        "letmein123",
        "iloveyou1",
        "welcome123",
        "admin1234",
        "changeme1",
        "ats123456",
        "atsonework",
    }
)


def validate_password_strength(password: str, *, email: str | None = None) -> str | None:
    """Return a reason the password is too weak, or None when it is fine.

    Deliberately modest: length is what actually matters, so the rules
    are a length floor, a check against the common passwords, and a
    check that the password is not the account's own email or a part of
    it. Anything stricter pushes people towards writing their password
    on a sticky note.
    """
    if len(password) < 8:
        return "The password must be at least 8 characters long."
    if len(password) > 128:
        return "The password must be at most 128 characters long."
    if password.lower() in TOO_COMMON:
        return "That password is too common. Choose something less predictable."
    if email:
        local_part = email.split("@")[0].lower()
        lowered = password.lower()
        if len(local_part) >= 4 and (lowered == local_part or lowered == email.lower()):
            return "The password must not be your email address."
    return None
