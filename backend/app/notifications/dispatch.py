"""Notification delivery hooks — router-side helpers (arch. doc §38).

Services persist ``notifications`` rows inside their own workflow transaction.
This module schedules *external* delivery (push/email) after that transaction
commits. Routers use ``enqueue_notification_dispatch`` with FastAPI's
``BackgroundTasks`` — delivery is fire-and-forget and never awaited inline.
``NotificationSender`` is a provider interface (§39): the default
implementation is a no-op logger, so domain code has no provider imports.
Production wires a real push/email sender here without touching domains.
"""

from __future__ import annotations

import logging

from fastapi import BackgroundTasks

from app.notifications.schemas import NotificationResponse

logger = logging.getLogger(__name__)


class NotificationSender:
    """Provider interface (§39) — swap with a real push/email sender."""

    async def send(self, notification: NotificationResponse) -> None:
        logger.info(
            "notification dispatch (noop sender): %s",
            notification.notification_id,
            extra={
                "notification_id": notification.notification_id,
                "employee_id": notification.employee_id,
            },
        )


_sender: NotificationSender | None = None


def get_sender() -> NotificationSender:
    """Process-wide sender — replaceable in tests and production wiring."""
    global _sender
    if _sender is None:
        _sender = NotificationSender()
    return _sender


def set_sender(sender: NotificationSender | None) -> None:
    """Override the sender (tests) — pass ``None`` to reset to the default."""
    global _sender
    _sender = sender


async def _deliver(notification: NotificationResponse) -> None:
    await get_sender().send(notification)


def enqueue_notification_dispatch(
    background: BackgroundTasks,
    notification: NotificationResponse,
) -> None:
    """Schedule external delivery after the workflow transaction commits.

    Routers call this — services never touch ``BackgroundTasks`` (§38).
    """
    background.add_task(_deliver, notification)
