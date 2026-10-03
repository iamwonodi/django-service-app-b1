from django.apps import AppConfig


class PollsConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.polls'
    # Pinned: the label names the existing tables (polls_question ...) and the
    # migration history, which the new dotted path must not rename.
    label = 'polls'
