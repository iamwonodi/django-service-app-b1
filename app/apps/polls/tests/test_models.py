import datetime

from django.test import TestCase
from django.utils import timezone

from apps.polls.models import Choice, Question


class QuestionModelTests(TestCase):
    def question(self, **offset):
        return Question(question_text="?", pub_date=timezone.now() + datetime.timedelta(**offset))

    def test_a_future_question_was_not_published_recently(self):
        self.assertIs(self.question(days=30).was_published_recently(), False)

    def test_an_old_question_was_not_published_recently(self):
        self.assertIs(self.question(days=-1, seconds=-1).was_published_recently(), False)

    def test_a_question_from_the_last_day_was_published_recently(self):
        self.assertIs(self.question(hours=-23, minutes=-59).was_published_recently(), True)

    def test_the_label_is_unchanged_so_the_existing_tables_still_belong_to_it(self):
        # The code moved to apps.polls; the tables and migration history did not.
        self.assertEqual(Question._meta.app_label, "polls")
        self.assertEqual(Question._meta.db_table, "polls_question")
        self.assertEqual(Choice._meta.db_table, "polls_choice")

    def test_str_is_the_text(self):
        self.assertEqual(str(Question(question_text="Why?")), "Why?")
        self.assertEqual(str(Choice(choice_text="Because")), "Because")
