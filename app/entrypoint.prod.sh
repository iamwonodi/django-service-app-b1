#!/bin/sh
set -eu

# ==============================================================================
# CONTAINER ENTRYPOINT
#
# Migrates the database (under a lock, so containers starting together do not
# collide -- see migrate.py), then replaces this shell with gunicorn so that it is
# PID 1 and receives the stop signal directly.
#
# collectstatic is NOT run here. It runs once, when the image is built, and the
# pipeline uploads its output; running it at every start would slow every deploy
# and write into a filesystem the container may not own.
#
# DJANGO_RUN_MIGRATIONS=false skips the migration step, for a container that must
# start against a database another release has not migrated yet.
# ==============================================================================

if [ "${DJANGO_RUN_MIGRATIONS:-true}" = "true" ]; then
  python migrate.py
fi

exec gunicorn --config gunicorn.conf.py app.wsgi:application
