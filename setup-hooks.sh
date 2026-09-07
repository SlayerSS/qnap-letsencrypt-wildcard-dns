#!/bin/sh
# Enable repo hooks that block Cursor co-author trailers in commits.
set -eu
chmod +x .githooks/commit-msg
git config core.hooksPath .githooks
echo "Git hooks enabled (.githooks/commit-msg)"
