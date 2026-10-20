"""Receipt upload verification — no database required.

The stored extension comes from the file's own bytes, so a part that
declares itself as a JPEG but carries HTML is rejected instead of being
written to disk and later served as ``text/html``.
"""

from __future__ import annotations

import pytest

from app.core.exceptions import ValidationError
from app.expenses.uploads import sniff_content_type, verify_upload

JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00"
PNG = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
PDF = b"%PDF-1.7\n%\xe2\xe3\xcf\xd3"
WEBP = b"RIFF\x24\x00\x00\x00WEBPVP8 "


@pytest.mark.parametrize(
    ("content", "content_type", "extension"),
    [
        (JPEG, "image/jpeg", ".jpg"),
        (PNG, "image/png", ".png"),
        (PDF, "application/pdf", ".pdf"),
        (WEBP, "image/webp", ".webp"),
    ],
)
def test_recognised_formats(content: bytes, content_type: str, extension: str) -> None:
    sniffed = sniff_content_type(content)
    assert sniffed is not None
    assert sniffed.content_type == content_type
    assert sniffed.extension == extension


def test_html_is_not_a_receipt() -> None:
    """The stored-XSS payload: a real HTML document named like a receipt."""
    html = b"<!DOCTYPE html><html><script>alert(1)</script></html>"
    assert sniff_content_type(html) is None
    with pytest.raises(ValidationError):
        verify_upload("receipt.jpg", html)


def test_declared_type_does_not_override_the_bytes() -> None:
    """A client that lies about the type still gets the type of its bytes."""
    verified = verify_upload("receipt.html", JPEG)
    assert verified.content_type == "image/jpeg"
    assert verified.extension == ".jpg"


def test_generic_content_type_is_accepted_for_a_real_image() -> None:
    """Flutter sends application/octet-stream for real camera photos."""
    verified = verify_upload("receipt.jpg", JPEG)
    assert verified.content_type == "image/jpeg"


def test_executable_content_is_rejected() -> None:
    with pytest.raises(ValidationError):
        verify_upload("payload.exe", b"MZ\x90\x00")


def test_empty_file_is_rejected() -> None:
    with pytest.raises(ValidationError):
        verify_upload("receipt.jpg", b"")


def test_script_inside_a_pdf_header_is_still_a_pdf() -> None:
    """Sniffing looks at the signature, not at the whole document."""
    content = PDF + b"1 0 obj << /JS (alert(1)) >> endobj"
    verified = verify_upload("invoice.pdf", content)
    assert verified.content_type == "application/pdf"
