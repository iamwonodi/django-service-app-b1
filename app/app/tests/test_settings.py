"""
Settings are evaluated when Django starts, so each case runs in a fresh
interpreter with exactly the environment under test.
"""

import json
import subprocess
import sys
import textwrap
import unittest
from pathlib import Path

from ._environment import base_environment

APP_DIR = Path(__file__).resolve().parents[2]

PROBE = textwrap.dedent(
    """
    import json, os
    os.environ["DJANGO_SETTINGS_MODULE"] = "app.settings"
    try:
        from django.conf import settings
        s = settings
        print(json.dumps({
            "ok": True,
            "debug": s.DEBUG,
            "static_url": s.STATIC_URL,
            "allowed_hosts": s.ALLOWED_HOSTS,
            "csrf": s.CSRF_TRUSTED_ORIGINS,
            "engine": s.DATABASES["default"]["ENGINE"],
            "connect_timeout": s.DATABASES["default"].get("OPTIONS", {}).get("connect_timeout"),
            "db": {k: str(v) for k, v in s.DATABASES["default"].items()},
            "apps": list(s.INSTALLED_APPS),
            "hsts": s.SECURE_HSTS_SECONDS,
            "cookie_secure": s.SESSION_COOKIE_SECURE,
            "proxy_header": list(s.SECURE_PROXY_SSL_HEADER),
        }))
    except Exception as error:
        print(json.dumps({"ok": False, "error": type(error).__name__, "message": str(error)}))
    """
)

BASE_ENV = {
    "DJANGO_SECRET_KEY": "test-secret",
    "DJANGO_ALLOWED_HOSTS": "svc.example.org",
    # What the operating system needs for the child to start at all.
    **base_environment(),
    "PYTHONPATH": str(APP_DIR),
}


def load(**overrides):
    """Import settings with BASE_ENV plus overrides (a value of None removes a variable)."""
    env = dict(BASE_ENV)
    for key, value in overrides.items():
        if value is None:
            env.pop(key, None)
        else:
            env[key] = value
    result = subprocess.run(
        [sys.executable, "-c", PROBE], env=env, cwd=APP_DIR, capture_output=True, text=True, timeout=60
    )
    return json.loads(result.stdout.strip().splitlines()[-1])


POSTGRES_ENV = {
    "DATABASE_ENGINE": "postgres",
    "DATABASE_HOST": "db.example.org",
    "DATABASE_PORT": "20001",
    "DATABASE_NAME": "auth",
    "DATABASE_USERNAME": "auth",
    "DATABASE_PASSWORD": "pw",
}


class RequiredSettingsTests(unittest.TestCase):
    def test_a_missing_secret_key_fails_and_names_the_cause(self):
        result = load(DJANGO_SECRET_KEY=None)
        self.assertFalse(result["ok"])
        self.assertIn("APP_SECRET_ARN", result["message"])

    def test_an_empty_secret_key_fails_too(self):
        self.assertFalse(load(DJANGO_SECRET_KEY="")["ok"])

    def test_debug_may_omit_the_secret_key(self):
        result = load(DJANGO_SECRET_KEY=None, DJANGO_DEBUG="true")
        self.assertTrue(result["ok"])

    def test_missing_allowed_hosts_fails_in_production(self):
        result = load(DJANGO_ALLOWED_HOSTS=None)
        self.assertFalse(result["ok"])
        self.assertIn("DJANGO_ALLOWED_HOSTS", result["message"])

    def test_debug_defaults_allowed_hosts_to_localhost(self):
        result = load(DJANGO_ALLOWED_HOSTS=None, DJANGO_DEBUG="1")
        self.assertIn("localhost", result["allowed_hosts"])

    def test_debug_is_off_by_default(self):
        self.assertFalse(load()["debug"])


class SecurityTests(unittest.TestCase):
    def test_the_proxy_header_and_secure_cookies(self):
        result = load()
        self.assertEqual(result["proxy_header"], ["HTTP_X_FORWARDED_PROTO", "https"])
        self.assertTrue(result["cookie_secure"])

    def test_hsts_is_off_until_asked_for(self):
        self.assertEqual(load()["hsts"], 0)
        self.assertEqual(load(DJANGO_SECURE_HSTS_SECONDS="3600")["hsts"], 3600)

    def test_csrf_origins_are_a_clean_list(self):
        result = load(DJANGO_CSRF_TRUSTED_ORIGINS=" https://a.example.org , https://b.example.org ,")
        self.assertEqual(result["csrf"], ["https://a.example.org", "https://b.example.org"])


class StaticFilesTests(unittest.TestCase):
    def test_static_url_names_the_service(self):
        self.assertEqual(load(SERVICE_NAME="auth")["static_url"], "/static/auth/")

    def test_static_url_has_a_default(self):
        self.assertEqual(load()["static_url"], "/static/app/")


class DevelopmentToolingTests(unittest.TestCase):
    def test_browser_reload_is_not_loaded_in_production(self):
        self.assertNotIn("django_browser_reload", load()["apps"])

    def test_browser_reload_is_loaded_in_debug_when_installed(self):
        try:
            import django_browser_reload  # noqa: F401
        except ImportError:
            self.skipTest("django-browser-reload is not installed (requirements-dev.txt)")
        self.assertIn("django_browser_reload", load(DJANGO_DEBUG="true")["apps"])


class DatabaseTests(unittest.TestCase):
    def test_sqlite_is_the_default(self):
        self.assertEqual(load()["engine"], "django.db.backends.sqlite3")

    def test_the_platform_name_postgres_maps_to_djangos_postgresql(self):
        result = load(**POSTGRES_ENV)
        self.assertEqual(result["engine"], "django.db.backends.postgresql")
        self.assertEqual(result["db"]["HOST"], "db.example.org")
        self.assertEqual(result["db"]["PORT"], "20001")
        self.assertEqual(result["db"]["CONN_MAX_AGE"], "60")

    def test_every_connection_attempt_is_bounded(self):
        # A dropped packet must fail an attempt in seconds, not the OS's TCP timeout.
        self.assertEqual(load(**POSTGRES_ENV)["connect_timeout"], 5)
        self.assertEqual(load(**dict(POSTGRES_ENV, DATABASE_CONNECT_TIMEOUT="2"))["connect_timeout"], 2)

    def test_mysql_is_supported(self):
        env = dict(POSTGRES_ENV, DATABASE_ENGINE="mysql")
        self.assertEqual(load(**env)["engine"], "django.db.backends.mysql")

    def test_each_missing_variable_is_reported(self):
        for name in ("DATABASE_HOST", "DATABASE_PORT", "DATABASE_NAME", "DATABASE_USERNAME", "DATABASE_PASSWORD"):
            with self.subTest(missing=name):
                env = dict(POSTGRES_ENV)
                env[name] = None
                result = load(**env)
                self.assertFalse(result["ok"])
                self.assertIn(name, result["message"])

    def test_an_unsupported_engine_is_rejected(self):
        result = load(DATABASE_ENGINE="mongodb")
        self.assertFalse(result["ok"])
        self.assertIn("mongodb", result["message"])
