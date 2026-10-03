from io import StringIO

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase


class MigrationsTests(TestCase):
    def test_the_models_and_the_migrations_agree(self):
        # The same as "python manage.py makemigrations --check --dry-run": a model
        # edited without its migration is caught here, not on the first deploy.
        try:
            call_command("makemigrations", check=True, dry_run=True, stdout=StringIO())
        except CommandError:  # pragma: no cover - the message below is the point
            self.fail("makemigrations --check found model changes with no migration")
