from django.test import Client, TestCase, override_settings

PLAIN_STATIC = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
}


@override_settings(STORAGES=PLAIN_STATIC)
class PagesTests(TestCase):
    def test_polls_index_renders_with_its_stylesheet(self):
        response = Client(HTTP_HOST="testserver").get("/polls/")
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "polls/style.css")

    def test_the_reload_endpoint_does_not_exist_without_debug(self):
        response = Client(HTTP_HOST="testserver", raise_request_exception=False).get("/__reload__/events/")
        self.assertEqual(response.status_code, 404)
