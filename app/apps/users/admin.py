from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import User

# The stock UserAdmin is enough: Django builds its add and change forms for the
# admin's own model, so the swapped-out auth.User is never touched (the tests
# open both forms to prove it).
admin.site.register(User, UserAdmin)
