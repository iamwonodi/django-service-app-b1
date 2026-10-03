from django.test import RequestFactory, SimpleTestCase

from apps.core.utils import safe_next_url


class SafeNextUrlTests(SimpleTestCase):
    def target(self, path, **extra):
        return safe_next_url(RequestFactory().get(path, **extra), "/home/")

    def test_a_local_path_is_kept(self):
        self.assertEqual(self.target("/login/?next=/polls/"), "/polls/")

    def test_another_host_falls_back(self):
        self.assertEqual(self.target("/login/?next=https://evil.example/"), "/home/")

    def test_a_scheme_relative_url_falls_back(self):
        self.assertEqual(self.target("/login/?next=//evil.example/"), "/home/")

    def test_a_missing_value_falls_back(self):
        self.assertEqual(self.target("/login/"), "/home/")

    def test_the_posted_value_is_read_too(self):
        request = RequestFactory().post("/login/", {"next": "/polls/"})
        self.assertEqual(safe_next_url(request, "/home/"), "/polls/")

    def test_http_is_refused_when_the_request_is_https(self):
        request = RequestFactory().get("/login/?next=http://testserver/x/", secure=True)
        self.assertEqual(safe_next_url(request, "/home/"), "/home/")
