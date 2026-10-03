from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic import TemplateView

from apps.core.mixins import PageTitleMixin


class ProfileView(LoginRequiredMixin, PageTitleMixin, TemplateView):
    """The signed-in user's own details; ``user`` comes from the auth context processor."""

    template_name = "users/profile.html"
    page_title = "Your profile"
