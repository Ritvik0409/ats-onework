"""Receipt upload validation (arch. doc §15, §32).

The file's *bytes* decide what it is, not the ``Content-Type`` header the
client sent and not the filename it chose. Both are attacker-controlled:
a part declared ``image/jpeg`` with the name ``receipt.html`` would
otherwise be written to disk and later served as ``text/html`` by the
static file mount, which is a stored-XSS hole on the API's own origin.

So the content type is sniffed from the leading bytes and the stored
extension is chosen server-side from that result. A file whose bytes are
not a JPEG, PNG, WebP or PDF is rejected outright.
"""

from __future__ import annotations

from dataclasses import dataclass

from app.core.exceptions import ValidationError

# Leading-byte signatures, longest/most specific first.
_SIGNATURES: tuple[tuple[bytes, str, str], ...] = (
    (b"\x89PNG\r\n\x1a\n", "image/png", ".png"),
    (b"%PDF-", "application/pdf", ".pdf"),
    (b"\xff\xd8\xff", "image/jpeg", ".jpg"),
)

_WEBP_RIFF = b"RIFF"
_WEBP_TAG = b"WEBP"

#: Extension → content type, for the store's own bookkeeping.
CONTENT_TYPE_EXTENSIONS: dict[str, str] = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "application/pdf": ".pdf",
}


@dataclass(frozen=True, slots=True)
class SniffedFile:
    """A verified upload: what it is, and how it should be stored."""

    content_type: str
    extension: str


def sniff_content_type(content: bytes) -> SniffedFile | None:
    """Identify an upload from its leading bytes, or ``None`` if unknown."""
    for signature, content_type, extension in _SIGNATURES:
        if content.startswith(signature):
            return SniffedFile(content_type=content_type, extension=extension)
    # WebP is a RIFF container: "RIFF" .... "WEBP".
    if len(content) >= 12 and content[:4] == _WEBP_RIFF and content[8:12] == _WEBP_TAG:
        return SniffedFile(content_type="image/webp", extension=".webp")
    return None


def verify_upload(filename: str | None, content: bytes) -> SniffedFile:
    """Validate an uploaded receipt and return its verified type.

    The declared ``Content-Type`` is intentionally ignored: Flutter's
    ``MultipartFile.fromBytes`` sends ``application/octet-stream`` even
    for a real JPEG, and a client that declares the wrong type is not
    more trustworthy than one that declares nothing. The bytes are the
    only reliable signal.
    """
    sniffed = sniff_content_type(content)
    if sniffed is None:
        raise ValidationError(
            f"File {filename or 'receipt'} is not a supported receipt."
            " Accepted: jpeg, png, webp, pdf."
        )
    return sniffed
