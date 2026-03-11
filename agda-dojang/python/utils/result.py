"""
file: agda-native-air/agda-dojang/python/utils/result.py
description: tiny Result type
copyright: 2025 Thmpr
"""
from __future__ import annotations
from dataclasses import dataclass
from typing import Generic, TypeVar, Callable, Union, Any

T = TypeVar("T"); E = TypeVar("E"); U = TypeVar("U")

@dataclass(frozen=True)
class Ok(Generic[T]):
    value: T

@dataclass(frozen=True)
class Err(Generic[E]):
    error: E

Result = Union[Ok[T], Err[E]]

def is_ok(r: Result[Any, Any]) -> bool:
    return isinstance(r, Ok)

def is_err(r: Result[Any, Any]) -> bool:
    return isinstance(r, Err)

def map_result(fn: Callable[[T], U], r: Result[T, E]) -> Result[U, E]:
    return Ok(fn(r.value)) if isinstance(r, Ok) else r  # keeps our original

def and_then(fn: Callable[[T], Result[U, E]], r: Result[T, E]) -> Result[U, E]:
    return fn(r.value) if isinstance(r, Ok) else r

def map_err(fn: Callable[[E], E], r: Result[T, E]) -> Result[T, E]:
    return Err(fn(r.error)) if isinstance(r, Err) else r

def unwrap_or(default: T, r: Result[T, Any]) -> T:
    return r.value if isinstance(r, Ok) else default
