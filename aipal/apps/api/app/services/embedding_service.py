from __future__ import annotations

import hashlib
import math
import re

_DIM = 1536


def embed_text(text: str, *, dim: int = _DIM) -> list[float]:
    """Deterministic lightweight embedding for semantic retrieval."""
    vec = [0.0] * dim
    tokens = re.findall(r"[a-z0-9']+", (text or "").lower())
    if not tokens:
        return vec

    for idx, token in enumerate(tokens):
        digest = hashlib.sha256(token.encode("utf-8")).digest()
        bucket = int.from_bytes(digest[:4], "big") % dim
        weight = 1.0 + (idx % 5) * 0.05
        vec[bucket] += weight
        vec[(bucket * 7 + 13) % dim] += weight * 0.35

    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [v / norm for v in vec]


def cosine_similarity(left: list[float] | None, right: list[float] | None) -> float:
    if not left or not right:
        return 0.0
    size = min(len(left), len(right))
    dot = sum(left[i] * right[i] for i in range(size))
    lnorm = math.sqrt(sum(v * v for v in left[:size])) or 1.0
    rnorm = math.sqrt(sum(v * v for v in right[:size])) or 1.0
    return dot / (lnorm * rnorm)
