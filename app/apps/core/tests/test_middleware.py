from django.conf import settings
from django.test import Client, SimpleTestCase


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

    def test_it_is_first_in_the_middleware_stack(self):
        # SecurityMiddleware and CommonMiddleware both call get_host(); any of them
        # ahead of this one would reject the load balancer's IP before it answered.
        self.assertEqual(settings.MIDDLEWARE[0], "apps.core.middleware.HealthCheckMiddleware")
