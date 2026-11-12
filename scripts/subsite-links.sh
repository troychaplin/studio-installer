#!/bin/bash

# Makes subdirectory-multisite admin work under WordPress Studio.
#
# Studio serves sites with PHP's built-in server and its own router, which
# ignores .htaccess. Apache/nginx rewrite /<subsite>/wp-admin/ (and wp-includes,
# wp-content, wp-*.php) to the real files at the root. Studio sends those
# requests to index.php instead, and WordPress redirects them to themselves
# in a loop.
#
# This script gives each subsite a folder of symlinks pointing back to the
# real files, so the router finds them. The folders have no index.php, so
# subsite front-end pages still go through WordPress as normal.
#
# Re-run it after adding a subsite. The site must be running.
#
# Usage: scripts/subsite-links.sh [--path=<site folder>]   (default: current folder)

set -euo pipefail

SITE_PATH="$PWD"
for arg in "$@"; do
    case "$arg" in
        --path=*) SITE_PATH="${arg#--path=}" ;;
        -h|--help) sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

if [ ! -f "$SITE_PATH/wp-load.php" ]; then
    echo "Error: $SITE_PATH doesn't look like a WordPress folder (no wp-load.php)."
    exit 1
fi
cd "$SITE_PATH"

TARGETS=(
    wp-admin wp-includes wp-content
    wp-login.php wp-signup.php wp-activate.php wp-cron.php
    wp-comments-post.php wp-trackback.php wp-links-opml.php wp-mail.php
    xmlrpc.php
)

# One path per subsite, e.g. "/news/". The main site ("/") is skipped.
# Uses WP-CLI through Studio, so it works with SQLite and MySQL alike.
PATHS=$(studio wp --path="$SITE_PATH" site list --field=path 2>/dev/null | grep -E '^/[_0-9a-zA-Z-]+/$' || true)

if [ -z "$PATHS" ]; then
    echo "No subdirectory subsites found (is the Studio site running and set up as a network?)."
    exit 0
fi

for p in $PATHS; do
    slug="${p#/}"
    slug="${slug%/}"

    # Never touch a real file or folder of the same name.
    if [ -e "$slug" ] && [ ! -f "$slug/.studio-subsite-links" ]; then
        echo "Skipping $slug/: a directory or file with that name already exists."
        continue
    fi

    mkdir -p "$slug"
    touch "$slug/.studio-subsite-links"
    for t in "${TARGETS[@]}"; do
        ln -sfn "../$t" "$slug/$t"
    done

    echo "Linked /$slug/"
done
