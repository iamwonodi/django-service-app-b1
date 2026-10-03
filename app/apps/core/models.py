from django.db import models


class TimeStampedModel(models.Model):
    """Abstract base: when a row was created and when it was last saved."""

    created = models.DateTimeField(auto_now_add=True)
    # auto_now only fires on save(); QuerySet.update() and bulk_update() skip it,
    # so pass updated explicitly when using them.
    updated = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True
