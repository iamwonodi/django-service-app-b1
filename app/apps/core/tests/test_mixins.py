from django.test import RequestFactory, SimpleTestCase
from django.views.generic import TemplateView

from apps.core.mixins import PageTitleMixin


class TitledView(PageTitleMixin, TemplateView):
    template_name = "unused.html"
    page_title = "Hello"


class DynamicView(PageTitleMixin, TemplateView):
    template_name = "unused.html"

    def get_page_title(self):
        return "Computed"


class PageTitleMixinTests(SimpleTestCase):
    def context(self, view_class):
        view = view_class()
        view.setup(RequestFactory().get("/"))
        return view.get_context_data()

    def test_the_attribute_reaches_the_context(self):
        self.assertEqual(self.context(TitledView)["page_title"], "Hello")

    def test_a_view_can_compute_it(self):
        self.assertEqual(self.context(DynamicView)["page_title"], "Computed")
