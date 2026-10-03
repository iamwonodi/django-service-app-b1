import datetime
from unittest import mock

from django.db import connection, models
from django.test import TransactionTestCase
from django.utils import timezone

from apps.core.models import TimeStampedModel


class Stamped(TimeStampedModel):
    """A concrete model for the tests only; no migration exists for it."""

    name = models.CharField(max_length=20)

    class Meta:
        app_label = "core"


class TimeStampedModelTests(TransactionTestCase):
    # The test runner already creates this table when it imported this module before
    # building the test database (an app without migrations is synced), but not when
    # the model arrives later; make the table either way and leave things as found.
    # TransactionTestCase because SQLite cannot change schema inside a TestCase's
    # transaction.
    def setUp(self):
        if Stamped._meta.db_table not in connection.introspection.table_names():
            with connection.schema_editor() as editor:
                editor.create_model(Stamped)
            self.addCleanup(self.drop_table)

    @staticmethod
    def drop_table():
        with connection.schema_editor() as editor:
            editor.delete_model(Stamped)

    def test_the_model_is_abstract(self):
        self.assertTrue(TimeStampedModel._meta.abstract)

    def test_created_and_updated_are_set_on_the_first_save(self):
        before = timezone.now()
        row = Stamped.objects.create(name="a")
        self.assertGreaterEqual(row.created, before)
        self.assertLessEqual(row.created, timezone.now())
        self.assertLess(row.updated - row.created, datetime.timedelta(seconds=1))

    def test_updated_moves_on_a_later_save_and_created_does_not(self):
        row = Stamped.objects.create(name="a")
        created = row.created
        later = created + datetime.timedelta(hours=1)
        with mock.patch("django.utils.timezone.now", return_value=later):
            row.name = "b"
            row.save()
        row.refresh_from_db()
        self.assertEqual(row.created, created)
        self.assertEqual(row.updated, later)
