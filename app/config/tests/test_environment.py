from django.test import SimpleTestCase


class ChildEnvironmentTests(SimpleTestCase):
    """The minimal environment the settings and migrate tests give a child Python.

    On Windows a child without SYSTEMROOT cannot import asyncio (WinError 10106),
    which Django imports on every start, so every subprocess test failed there.
    """

    def test_it_carries_the_windows_variables_when_they_exist(self):
        from unittest import mock

        from ._environment import base_environment

        windows = {"PATH": r"C:\Windows", "SYSTEMROOT": r"C:\Windows", "WINDIR": r"C:\Windows", "DJANGO_SECRET_KEY": "x"}
        with mock.patch.dict("os.environ", windows, clear=True):
            env = base_environment()

        self.assertEqual(env["SYSTEMROOT"], r"C:\Windows")
        self.assertEqual(env["WINDIR"], r"C:\Windows")

    def test_it_carries_nothing_the_application_reads(self):
        from unittest import mock

        from ._environment import base_environment

        with mock.patch.dict("os.environ", {"PATH": "/bin", "DJANGO_SECRET_KEY": "x", "DATABASE_HOST": "db"}, clear=True):
            env = base_environment()

        self.assertEqual(env, {"PATH": "/bin"})
