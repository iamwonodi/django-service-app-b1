from django.test import TestCase, override_settings
from django.urls import reverse

from apps.core.tests.support import PLAIN_STATIC

from .factories import PASSWORD, SuperuserFactory, UserFactory


@override_settings(STORAGES=PLAIN_STATIC)
class LoginTests(TestCase):
    def test_the_page_renders_inside_the_project_layout(self):
        response = self.client.get(reverse("users:login"))
        self.assertEqual(response.status_code, 200)
        self.assertTemplateUsed(response, "users/login.html")
        self.assertTemplateUsed(response, "base.html")

    def test_valid_credentials_sign_in_and_go_to_the_profile(self):
        user = UserFactory()
        response = self.client.post(reverse("users:login"), {"username": user.username, "password": PASSWORD})
        self.assertRedirects(response, reverse("users:profile"))
        self.assertEqual(int(self.client.session["_auth_user_id"]), user.pk)

    def test_wrong_credentials_stay_on_the_page_with_an_error(self):
        user = UserFactory()
        response = self.client.post(reverse("users:login"), {"username": user.username, "password": "wrong"})
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.context["form"].errors)
        self.assertNotIn("_auth_user_id", self.client.session)

    def test_next_is_honoured_for_a_local_path_only(self):
        user = UserFactory()
        data = {"username": user.username, "password": PASSWORD}
        local = self.client.post(reverse("users:login"), {**data, "next": "/polls/"})
        self.assertRedirects(local, "/polls/", fetch_redirect_response=False)
        self.client.logout()
        foreign = self.client.post(reverse("users:login"), {**data, "next": "https://evil.example/"})
        self.assertRedirects(foreign, reverse("users:profile"), fetch_redirect_response=False)

    def test_logout_is_post_only_and_signs_out(self):
        self.client.force_login(UserFactory())
        self.assertEqual(self.client.get(reverse("users:logout")).status_code, 405)
        response = self.client.post(reverse("users:logout"))
        self.assertRedirects(response, reverse("users:login"))
        self.assertNotIn("_auth_user_id", self.client.session)


@override_settings(STORAGES=PLAIN_STATIC)
class ProfileTests(TestCase):
    def test_it_requires_login(self):
        response = self.client.get(reverse("users:profile"))
        self.assertRedirects(response, f"{reverse('users:login')}?next={reverse('users:profile')}")

    def test_it_shows_the_signed_in_user_inside_the_project_layout(self):
        user = UserFactory(username="grace", email="grace@example.com")
        self.client.force_login(user)
        response = self.client.get(reverse("users:profile"))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "grace@example.com")
        self.assertTemplateUsed(response, "users/profile.html")
        self.assertTemplateUsed(response, "base.html")
        self.assertContains(response, "<title>Your profile</title>")


@override_settings(STORAGES=PLAIN_STATIC)
class AdminTests(TestCase):
    """The stock UserAdmin must work against the swapped-in model."""

    def setUp(self):
        self.client.force_login(SuperuserFactory())

    def test_the_user_list_loads(self):
        self.assertEqual(self.client.get(reverse("admin:users_user_changelist")).status_code, 200)

    def test_a_user_can_be_added(self):
        response = self.client.post(
            reverse("admin:users_user_add"),
            {"username": "new", "password1": "a-long-test-pass-9x", "password2": "a-long-test-pass-9x"},
        )
        self.assertEqual(response.status_code, 302, getattr(response, "context", None))
        from apps.users.models import User

        self.assertTrue(User.objects.filter(username="new").exists())

    def test_a_user_can_be_changed(self):
        user = UserFactory()
        self.assertEqual(self.client.get(reverse("admin:users_user_change", args=(user.pk,))).status_code, 200)
