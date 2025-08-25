#!/usr/bin/env python3
# file: python/utils/result.py
"""
description: tiny Result type
"""
from __future__ import annotations
from dataclasses import dataclass
from typing import Generic, TypeVar, Callable

T = TypeVar("T"); E = TypeVar("E")

@dataclass(frozen=True)
class Ok(Generic[T]):
    value: T

@dataclass(frozen=True)
class Err(Generic[E]):
    error: E

Result = Ok[T] | Err[E]  # python 3.10+: use typing.Union if needed

# Monadic helpers

def map_result(fn: Callable[[T], T], r: Result[T] | Result[E]):
    return Ok(fn(r.value)) if isinstance(r, Ok) else r
