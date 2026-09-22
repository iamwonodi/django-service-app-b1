#!/usr/bin/env python
"""
Apply database migrations exactly once, however many containers start together.

Every host in a fleet runs this before serving traffic, and a rolling deploy or a
secret rotation starts several containers at the same moment. Django's own
"migrate" takes no lock, so two of them could apply the same migration at once.
This wrapper takes a lock held in the database itself -- the one place every
container can see -- so one runs the migrations while the rest wait, then find
nothing left to do.

  PostgreSQL   session-level advisory lock  (pg_try_advisory_lock)
  MySQL        named lock                   (GET_LOCK)
  SQLite       no lock: one file, and SQLite already serialises writers

It also waits for the database to accept connections, because on a fresh boot the
database can lag the application.

Environment (all optional):
  MIGRATE_DB_WAIT      seconds to wait for the database          (default 120)
  MIGRATE_LOCK_TIMEOUT seconds to wait for the migration lock    (default 300)
"""

import os
import sys
import time
import zlib
from contextlib import contextmanager

POLL_SECONDS = 2


class MigrationLockTimeout(RuntimeError):
    """The lock was still held by another container when the timeout ran out."""


def _lock_id(name):
    """A stable 31-bit integer for a lock name (PostgreSQL locks take a number)."""
    return zlib.crc32(name.encode()) & 0x7FFFFFFF


def wait_for_database(connection, timeout, sleep=time.sleep, clock=time.monotonic):
    """Block until the database accepts a connection, or raise after `timeout`."""
    from django.db import OperationalError

    deadline = clock() + timeout
    while True:
        try:
            connection.ensure_connection()
            return
        except OperationalError as error:
            if clock() >= deadline:
                raise
            print(f"Waiting for the database: {error}", file=sys.stderr)
            sleep(POLL_SECONDS)


@contextmanager
def migration_lock(connection, name, timeout, sleep=time.sleep, clock=time.monotonic):
    """Hold a database-wide lock called `name` for the duration of the block."""
    vendor = connection.vendor

    if vendor == "postgresql":
        acquire = "SELECT pg_try_advisory_lock(%s)"
        release = "SELECT pg_advisory_unlock(%s)"
        key = _lock_id(name)
    elif vendor == "mysql":
        # A zero timeout makes GET_LOCK non-blocking, so this polls exactly like
        # the PostgreSQL branch and both honour the same overall timeout.
        acquire = "SELECT GET_LOCK(%s, 0)"
        release = "SELECT RELEASE_LOCK(%s)"
        key = name
    else:
        yield
        return

    deadline = clock() + timeout

    while True:
        with connection.cursor() as cursor:
            cursor.execute(acquire, [key])
            if cursor.fetchone()[0]:
                break
        if clock() >= deadline:
            raise MigrationLockTimeout(
                f"Another container held the migration lock '{name}' for {timeout} seconds."
            )
        print(f"Waiting for the migration lock '{name}' ...", file=sys.stderr)
        sleep(POLL_SECONDS)

    try:
        yield
    finally:
        # The lock belongs to this session, so it is released with the connection
        # anyway; releasing it explicitly lets the next container in immediately.
        try:
            with connection.cursor() as cursor:
                cursor.execute(release, [key])
        except Exception as error:  # noqa: BLE001 -- never mask the migration's own outcome
            print(f"Could not release the migration lock: {error}", file=sys.stderr)


def main():
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "app.settings")

    import django

    django.setup()

    from django.conf import settings
    from django.core.management import call_command
    from django.db import connection

    db_wait = int(os.environ.get("MIGRATE_DB_WAIT", "120"))
    lock_timeout = int(os.environ.get("MIGRATE_LOCK_TIMEOUT", "300"))

    wait_for_database(connection, db_wait)

    with migration_lock(connection, f"django-migrate-{settings.SERVICE_NAME}", lock_timeout):
        call_command("migrate", interactive=False, verbosity=1)

    return 0


if __name__ == "__main__":
    sys.exit(main())
