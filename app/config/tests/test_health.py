from django.test import Client, SimpleTestCase, TestCase, override_settings

PLAIN_STATIC = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
}


class HealthCheckTests(SimpleTestCase):
    """The load balancer checks each target by IP, so its Host header can never be allowed."""

    def test_health_answers_for_a_host_that_is_not_allowed(self):
        client = Client(HTTP_HOST="10.1.2.3")
        response = client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content, b"ok")

    def test_health_answers_for_localhost(self):
        self.assertEqual(Client(HTTP_HOST="localhost").get("/health").status_code, 200)

    def test_other_paths_still_reject_an_unknown_host(self):
        # Host validation must not be weakened for anything but /health.
        client = Client(HTTP_HOST="10.1.2.3", raise_request_exception=False)
        self.assertEqual(client.get("/polls/").status_code, 400)


@override_settings(STORAGES=PLAIN_STATIC)
class PagesTests(TestCase):
    def test_polls_index_renders_with_its_stylesheet(self):
        response = Client(HTTP_HOST="testserver").get("/polls/")
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "polls/style.css")

    def test_the_reload_endpoint_does_not_exist_without_debug(self):
        response = Client(HTTP_HOST="testserver", raise_request_exception=False).get("/__reload__/events/")
        self.assertEqual(response.status_code, 404)


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
