from django.conf import settings
from django.contrib.auth import get_user_model
from django.test import TestCase

from .factories import PASSWORD, UserFactory


class UserModelTests(TestCase):
    def test_the_project_uses_its_own_user_model(self):
        self.assertEqual(settings.AUTH_USER_MODEL, "users.User")
        self.assertEqual(get_user_model()._meta.label, "users.User")

    def test_create_user_hashes_the_password_and_grants_no_rights(self):
        user = get_user_model().objects.create_user("ada", "ada@example.com", "pw-for-the-test-1")
        self.assertNotEqual(user.password, "pw-for-the-test-1")
        self.assertTrue(user.check_password("pw-for-the-test-1"))
        self.assertTrue(user.is_active)
        self.assertFalse(user.is_staff)
        self.assertFalse(user.is_superuser)

    def test_create_superuser_is_staff_and_superuser(self):
        user = get_user_model().objects.create_superuser("root", "root@example.com", "pw-for-the-test-1")
        self.assertTrue(user.is_staff)
        self.assertTrue(user.is_superuser)

    def test_create_superuser_refuses_to_make_a_non_superuser(self):
        with self.assertRaises(ValueError):
            get_user_model().objects.create_superuser("root", "r@example.com", "pw", is_superuser=False)

    def test_the_username_is_unique(self):
        UserFactory(username="same")
        with self.assertRaises(Exception):
            UserFactory(username="same")

    def test_the_factory_user_signs_in_with_the_shared_password(self):
        self.assertTrue(UserFactory().check_password(PASSWORD))
