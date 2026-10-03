from django.contrib.auth.models import AbstractUser


class User(AbstractUser):
    """The project's user, swapped in with AUTH_USER_MODEL.

    Nothing is added yet. It exists now because the user model cannot be replaced
    once a service has migrated: every table that points at a user would have to
    be rebuilt. Add fields here (a phone number, a display name) when a service
    needs them; sign-in is by username, Django's default, because making the
    email the identity is a decision for the service (uniqueness, case,
    verification), not for the blueprint.
    """
