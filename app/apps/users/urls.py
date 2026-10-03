from django.contrib.auth import views as auth_views
from django.urls import path

from . import views

app_name = "users"
urlpatterns = [
    path(
        "login/",
        auth_views.LoginView.as_view(template_name="users/login.html", redirect_authenticated_user=True),
        name="login",
    ),
    # POST only (Django 5): a link that signs out can be triggered by any page.
    path("logout/", auth_views.LogoutView.as_view(), name="logout"),
    path("profile/", views.ProfileView.as_view(), name="profile"),
]
