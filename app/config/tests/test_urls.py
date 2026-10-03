from django.test import Client, SimpleTestCase


class UrlTests(SimpleTestCase):
    def test_the_reload_endpoint_does_not_exist_without_debug(self):
        response = Client(HTTP_HOST="testserver", raise_request_exception=False).get("/__reload__/events/")
        self.assertEqual(response.status_code, 404)
