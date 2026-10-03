import datetime

from django.test import Client, TestCase, override_settings
from django.urls import reverse
from django.utils import timezone

from apps.polls.models import Choice, Question

PLAIN_STATIC = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
}


def make_question(text, days=0):
    return Question.objects.create(question_text=text, pub_date=timezone.now() + datetime.timedelta(days=days))


@override_settings(STORAGES=PLAIN_STATIC)
class IndexViewTests(TestCase):
    def test_it_renders_with_its_stylesheet(self):
        response = Client(HTTP_HOST="testserver").get("/polls/")
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "polls/style.css")

    def test_it_extends_the_project_layout(self):
        response = self.client.get(reverse("polls:index"))
        self.assertTemplateUsed(response, "polls/base.html")
        self.assertTemplateUsed(response, "base.html")

    def test_no_questions(self):
        response = self.client.get(reverse("polls:index"))
        self.assertContains(response, "No polls are available.")
        self.assertQuerySetEqual(response.context["latest_question_list"], [])

    def test_a_future_question_is_not_listed(self):
        make_question("Future", days=30)
        past = make_question("Past", days=-1)
        response = self.client.get(reverse("polls:index"))
        self.assertQuerySetEqual(response.context["latest_question_list"], [past])


@override_settings(STORAGES=PLAIN_STATIC)
class DetailViewTests(TestCase):
    def test_a_future_question_is_a_404(self):
        future = make_question("Future", days=5)
        self.assertEqual(self.client.get(reverse("polls:detail", args=(future.id,))).status_code, 404)

    def test_a_past_question_is_shown(self):
        past = make_question("Past text", days=-5)
        response = self.client.get(reverse("polls:detail", args=(past.id,)))
        self.assertContains(response, "Past text")


@override_settings(STORAGES=PLAIN_STATIC)
class VoteTests(TestCase):
    def setUp(self):
        self.question = make_question("Q", days=-1)
        self.choice = Choice.objects.create(question=self.question, choice_text="A")

    def test_a_vote_is_counted_and_redirects_to_the_results(self):
        response = self.client.post(reverse("polls:vote", args=(self.question.id,)), {"choice": self.choice.id})
        self.assertRedirects(response, reverse("polls:results", args=(self.question.id,)))
        self.choice.refresh_from_db()
        self.assertEqual(self.choice.votes, 1)

    def test_no_choice_redisplays_the_form_with_an_error(self):
        response = self.client.post(reverse("polls:vote", args=(self.question.id,)))
        self.assertContains(response, "select a choice.")
        self.assertTemplateUsed(response, "base.html")

    def test_results_extend_the_project_layout(self):
        response = self.client.get(reverse("polls:results", args=(self.question.id,)))
        self.assertTemplateUsed(response, "base.html")
