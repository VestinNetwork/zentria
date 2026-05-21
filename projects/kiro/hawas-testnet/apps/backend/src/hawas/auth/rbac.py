from __future__ import annotations

from enum import StrEnum


class RoleName(StrEnum):
    USER = "user"
    APPROVER = "approver"
    ADMIN = "admin"


ROLE_PERMISSIONS: dict[RoleName, frozenset[str]] = {
    RoleName.USER: frozenset({"wallets:read", "intents:create", "intents:read", "audit:read"}),
    RoleName.APPROVER: frozenset({"approvals:read", "approvals:decide"}),
    RoleName.ADMIN: frozenset({"admin:policies", "admin:risk", "admin:agents", "admin:health"}),
}


def permissions_for_roles(roles: set[str]) -> set[str]:
    permissions: set[str] = set()
    for role in roles:
        permissions.update(ROLE_PERMISSIONS.get(RoleName(role), frozenset()))
    return permissions
