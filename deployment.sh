#!/bin/bash
# Fail loud if any step fails — silent failures here previously caused the
# migration:run step to be skipped, leaving the DB schemaless.
set -euo pipefail

BRANCH=$1

# install dependencies
npm install --include=dev

# Run migrations against the already-compiled dist/ (the tarball ships
# only dist/, so `nest build` would fail here — skip the premigration:run
# hook by calling typeorm directly).
npx typeorm migration:run -d dist/src/database/data-source

# Start or restart the app
pm2 restart "$BRANCH-ecosystem-config.json" || pm2 start "$BRANCH-ecosystem-config.json"
