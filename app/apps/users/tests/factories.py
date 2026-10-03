import unittest

try:
    import factory
except ImportError:
    # The first CI run installs the production requirements only, to prove the
    # application does not need a development tool; the tests that use the
    # factories are skipped there and run in the second pass.
    raise unittest.SkipTest("factory-boy is not installed (requirements-dev.txt)") from None

from apps.users.models import User

# Not a secret: the password every factory user signs in with in a test.
PASSWORD = "a-test-only-password-1"


class UserFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = User

    username = factory.Sequence(lambda n: f"user{n}")
    email = factory.LazyAttribute(lambda user: f"{user.username}@example.com")

    @classmethod
    def _create(cls, model_class, *args, **kwargs):
        # create_user hashes the password; a plain create() would store it as text.
        kwargs.setdefault("password", PASSWORD)
        return model_class.objects.create_user(*args, **kwargs)


class SuperuserFactory(UserFactory):
    @classmethod
    def _create(cls, model_class, *args, **kwargs):
        kwargs.setdefault("password", PASSWORD)
        return model_class.objects.create_superuser(*args, **kwargs)
