import sqlite3
from contextlib import closing
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import migrate

from ._environment import base_environment

APP_DIR = Path(__file__).resolve().parents[2]


class FakeCursor:
    def __init__(self, connection):
        self.connection = connection
        self.row = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, sql, params):
        self.connection.calls.append((sql, tuple(params)))
        if self.connection.fail_on and self.connection.fail_on in sql:
            raise RuntimeError("release failed")
        self.row = self.connection.responses.pop(0) if self.connection.responses else True

    def fetchone(self):
        return (self.row,)


class FakeConnection:
    def __init__(self, vendor, responses=None, fail_on=None):
        self.vendor = vendor
        self.responses = list(responses or [])
        self.fail_on = fail_on
        self.calls = []

    def cursor(self):
        return FakeCursor(self)


class Clock:
    """A clock that only moves when the code under test sleeps."""

    def __init__(self):
        self.now = 0.0
        self.sleeps = []

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds


class PostgresLockTests(unittest.TestCase):
    def test_acquires_then_releases_the_same_lock(self):
        connection, clock = FakeConnection("postgresql", [True]), Clock()
        with migrate.migration_lock(connection, "x", 60, clock.sleep, clock.monotonic):
            self.assertEqual(len(connection.calls), 1)
        self.assertIn("pg_try_advisory_lock", connection.calls[0][0])
        self.assertIn("pg_advisory_unlock", connection.calls[1][0])
        self.assertEqual(connection.calls[0][1], connection.calls[1][1])

    def test_waits_while_another_container_holds_it(self):
        connection, clock = FakeConnection("postgresql", [False, False, True]), Clock()
        with migrate.migration_lock(connection, "x", 60, clock.sleep, clock.monotonic):
            pass
        self.assertEqual(len(clock.sleeps), 2)

    def test_gives_up_after_the_timeout_and_never_releases_a_lock_it_never_held(self):
        connection, clock = FakeConnection("postgresql", [False] * 100), Clock()
        with self.assertRaises(migrate.MigrationLockTimeout):
            with migrate.migration_lock(connection, "x", 10, clock.sleep, clock.monotonic):
                self.fail("the block must not run without the lock")
        self.assertFalse(any("unlock" in sql for sql, _ in connection.calls))

    def test_releases_when_the_block_fails_and_lets_the_error_through(self):
        connection, clock = FakeConnection("postgresql", [True]), Clock()
        with self.assertRaises(ValueError):
            with migrate.migration_lock(connection, "x", 60, clock.sleep, clock.monotonic):
                raise ValueError("migration failed")
        self.assertIn("pg_advisory_unlock", connection.calls[-1][0])

    def test_a_failed_release_does_not_mask_the_result(self):
        connection, clock = FakeConnection("postgresql", [True], fail_on="unlock"), Clock()
        with migrate.migration_lock(connection, "x", 60, clock.sleep, clock.monotonic):
            pass  # must not raise

    def test_the_lock_number_is_stable_and_fits_31_bits(self):
        first = migrate._lock_id("django-migrate-auth")
        self.assertEqual(first, migrate._lock_id("django-migrate-auth"))
        self.assertNotEqual(first, migrate._lock_id("django-migrate-billing"))
        self.assertTrue(0 <= first < 2**31)


class MysqlLockTests(unittest.TestCase):
    def test_uses_a_named_lock(self):
        connection, clock = FakeConnection("mysql", [1]), Clock()
        with migrate.migration_lock(connection, "django-migrate-auth", 60, clock.sleep, clock.monotonic):
            pass
        self.assertIn("GET_LOCK", connection.calls[0][0])
        self.assertEqual(connection.calls[0][1], ("django-migrate-auth",))
        self.assertIn("RELEASE_LOCK", connection.calls[1][0])

    def test_polls_like_postgres(self):
        connection, clock = FakeConnection("mysql", [0, 0, 1]), Clock()
        with migrate.migration_lock(connection, "x", 60, clock.sleep, clock.monotonic):
            pass
        self.assertEqual(len(clock.sleeps), 2)


class SqliteLockTests(unittest.TestCase):
    def test_takes_no_lock(self):
        connection = FakeConnection("sqlite")
        with migrate.migration_lock(connection, "x", 60):
            pass
        self.assertEqual(connection.calls, [])


class WaitForDatabaseTests(unittest.TestCase):
    def setUp(self):
        from django.db import OperationalError

        self.error = OperationalError

    def make(self, failures):
        error = self.error

        class Connection:
            attempts = 0

            def ensure_connection(self):
                Connection.attempts += 1
                if Connection.attempts <= failures:
                    raise error("connection refused")

        return Connection()

    def test_returns_once_the_database_answers(self):
        clock = Clock()
        connection = self.make(failures=2)
        migrate.wait_for_database(connection, 60, clock.sleep, clock.monotonic)
        self.assertEqual(len(clock.sleeps), 2)

    def test_raises_after_the_timeout(self):
        clock = Clock()
        with self.assertRaises(self.error):
            migrate.wait_for_database(self.make(failures=10**6), 6, clock.sleep, clock.monotonic)


class MigrateScriptTests(unittest.TestCase):
    """The real script, against a real (SQLite) database."""

    def run_script(self, database):
        env = {
            **base_environment(),
            "DJANGO_SECRET_KEY": "test",
            "DJANGO_ALLOWED_HOSTS": "x",
            "DATABASE_ENGINE": "sqlite3",
            "DATABASE_NAME": database,
            "SERVICE_NAME": "auth",
        }
        return subprocess.run(
            [sys.executable, "migrate.py"], cwd=APP_DIR, env=env, capture_output=True, text=True, timeout=120
        )

    def test_migrates_and_is_safe_to_run_again(self):
        with tempfile.TemporaryDirectory() as directory:
            database = str(Path(directory) / "test.sqlite3")
            first = self.run_script(database)
            self.assertEqual(first.returncode, 0, first.stderr)

            # Closed explicitly: Windows cannot delete a file that is still open,
            # so a connection left to the garbage collector fails the cleanup.
            with closing(sqlite3.connect(database)) as connection:
                tables = {row[0] for row in connection.execute("select name from sqlite_master")}
            self.assertIn("polls_question", tables)
            self.assertIn("django_migrations", tables)

            second = self.run_script(database)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertIn("No migrations to apply", second.stdout)

    def test_an_unreachable_database_fails_after_waiting(self):
        env = {
            **base_environment(),
            "DJANGO_SECRET_KEY": "test",
            "DJANGO_ALLOWED_HOSTS": "x",
            "DATABASE_ENGINE": "postgres",
            "DATABASE_HOST": "127.0.0.1",
            "DATABASE_PORT": "1",
            "DATABASE_NAME": "n",
            "DATABASE_USERNAME": "u",
            "DATABASE_PASSWORD": "p",
            "MIGRATE_DB_WAIT": "3",
            # Port 1 is refused at once on Linux but may be silently dropped on
            # Windows; the connect timeout bounds each attempt either way.
            "DATABASE_CONNECT_TIMEOUT": "2",
        }
        result = subprocess.run(
            [sys.executable, "migrate.py"], cwd=APP_DIR, env=env, capture_output=True, text=True, timeout=60
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Waiting for the database", result.stderr)
