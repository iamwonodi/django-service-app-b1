from django.contrib.auth import get_user_model
from django.test import Client, TestCase, override_settings

from .support import PLAIN_STATIC


@override_settings(STORAGES=PLAIN_STATIC, DEBUG=False)
class ErrorPageTests(TestCase):
    def test_404_is_the_project_page_inside_the_layout(self):
        response = self.client.get("/no-such-page/")
        self.assertEqual(response.status_code, 404)
        self.assertTemplateUsed(response, "errors/404.html")
        self.assertTemplateUsed(response, "base.html")
        self.assertContains(response, "That page does not exist.", status_code=404)

    @override_settings(ROOT_URLCONF="apps.core.tests.urls")
    def test_500_is_the_standalone_project_page(self):
        with self.assertLogs("django.request", "ERROR"):
            response = Client(raise_request_exception=False).get("/boom/")
        self.assertEqual(response.status_code, 500)
        self.assertTemplateUsed(response, "errors/500.html")
        # Not the layout: that reads the session and the user, which may be what broke.
        self.assertTemplateNotUsed(response, "base.html")
        self.assertContains(response, "Something went wrong", status_code=500)


@override_settings(STORAGES=PLAIN_STATIC)
class LayoutTests(TestCase):
    def test_the_navbar_and_footer_are_on_every_page(self):
        response = self.client.get("/no-such-page/")
        self.assertTemplateUsed(response, "partials/navbar.html")
        self.assertTemplateUsed(response, "partials/footer.html")

    def test_an_anonymous_visitor_is_offered_sign_in(self):
        self.assertContains(self.client.get("/no-such-page/"), "Sign in", status_code=404)

    def test_a_signed_in_user_sees_their_name_and_sign_out(self):
        self.client.force_login(get_user_model().objects.create_user("ada", password="pw-for-the-test-1"))
        response = self.client.get("/no-such-page/")
        self.assertContains(response, "ada", status_code=404)
        self.assertContains(response, "Sign out", status_code=404)
        self.assertNotContains(response, "Sign in", status_code=404)
