from __future__ import annotations

import time
from collections import defaultdict, deque
from collections.abc import Callable

from fastapi import Depends, HTTPException, status

from .auth import get_current_user
from .models import User

_WINDOW_SECONDS = 60
_DEFAULT_LIMIT = 60
_BUCKETS: dict[str, tuple[int, deque[float]]] = {}
_LAST_CLEANUP = time.time()


async def _check(scope: str, user_id: str, limit: int = _DEFAULT_LIMIT, window_seconds: int = _WINDOW_SECONDS) -> None:
    global _LAST_CLEANUP
    key = f"{scope}:{user_id}"
    now = time.time()

    if now - _LAST_CLEANUP > 300:
        _LAST_CLEANUP = now
        for k in list(_BUCKETS.keys()):
            ws, b = _BUCKETS[k]
            while b and now - b[0] > ws:
                b.popleft()
            if not b:
                del _BUCKETS[k]

    if key not in _BUCKETS:
        _BUCKETS[key] = (window_seconds, deque())

    bucket_window, bucket = _BUCKETS[key]
    while bucket and now - bucket[0] > bucket_window:
        bucket.popleft()
    if len(bucket) >= limit:
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Rate limit exceeded")
    bucket.append(now)


def rate_limit_dependency(scope: str, limit: int = _DEFAULT_LIMIT, window_seconds: int = _WINDOW_SECONDS) -> Callable[..., object]:
    async def _dependency(
        user: User = Depends(get_current_user),
    ) -> None:
        await _check(scope, str(user.id), limit=limit, window_seconds=window_seconds)

    return _dependency
