#!/bin/bash

# Adds a subsite to a subdirectory multisite in WordPress Studio, then makes
# its /wp-admin/ work.
#
# Studio serves sites with PHP's built-in server and its own router, which
# ignores .htaccess. Apache/nginx rewrite /<subsite>/wp-admin/ (and wp-includes,
# wp-content, wp-*.php) to the real files at the root. Studio sends those
# requests to index.php instead, and WordPress redirects them to themselves
# in a loop. So after creating the subsite, this script gives every subsite a
# folder of symlinks pointing back to the real files. The folders have no
# index.php, so subsite pages still go through WordPress as normal. If the site
# folder is a git repo, the folders are added to .git/info/exclude.
#
# Usage: scripts/add-subsite.sh [options]
#
#   --slug=<slug>          Subsite path, e.g. "news" for /news/ (asked if missing)
#   --title=<title>        Subsite title                (default: from the slug)
#   --email=<email>        Subsite admin's email        (default: the network's super admin)
#   --path=<site folder>   The network's folder         (default: the folder above scripts/)
#   --links-only           Don't create a subsite; just add links for every
#                          subsite that has none, e.g. ones made in wp-admin
#   -h, --help             Show this help

set -euo pipefail

SITE_PATH="$(cd "$(dirname "$0")/.." && pwd)"
SLUG="" TITLE="" EMAIL=""
LINKS_ONLY=false

fail() { echo "Error: $1" >&2; exit 1; }

for arg in "$@"; do
    case "$arg" in
        --slug=*)     SLUG="${arg#*=}" ;;
        --title=*)    TITLE="${arg#*=}" ;;
        --email=*)    EMAIL="${arg#*=}" ;;
        --path=*)     SITE_PATH="${arg#*=}" ;;
        --links-only) LINKS_ONLY=true ;;
        -h|--help)    sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            fail "Unknown option: $arg (see --help)" ;;
    esac
done

SITE_PATH="${SITE_PATH%/}"
[ -f "$SITE_PATH/wp-load.php" ] || fail "$SITE_PATH doesn't look like a WordPress folder (no wp-load.php)."
command -v studio >/dev/null 2>&1 || fail "'studio' is not installed."
cd "$SITE_PATH"

site_wp() { studio wp --path="$SITE_PATH" "$@"; }

# Folder names a link folder must never replace: anything already in the site
# root that this script didn't make.
taken() { [ -e "$1" ] && [ ! -f "$1/.studio-subsite-links" ]; }

# ---------------------------------------------------------------------------
# 1. Create the subsite
# ---------------------------------------------------------------------------

if [ "$LINKS_ONLY" = false ]; then
    if ! grep -q "define( *'MULTISITE', *true" wp-config.php 2>/dev/null; then
        fail "$SITE_PATH isn't a multisite network."
    fi
    if grep -q "define( *'SUBDOMAIN_INSTALL', *true" wp-config.php; then
        fail "This network uses subdomains, which Studio can't serve."
    fi

    if [ -z "$SLUG" ]; then
        [ -t 0 ] || fail "Pass --slug=<slug>."
        read -r -p "Subsite slug (e.g. news for /news/): " SLUG
    fi
    SLUG="$(printf '%s' "$SLUG" | tr '[:upper:]' '[:lower:]')"
    SLUG="${SLUG#/}"
    SLUG="${SLUG%/}"
    [[ "$SLUG" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] \
        || fail "The slug can only have lowercase letters, numbers and hyphens, e.g. news or team-blog."

    # Check before creating the subsite: once it exists, a clash would leave
    # it without a working /wp-admin/.
    taken "$SLUG" && fail "'$SLUG' is already a file or folder in $SITE_PATH. Choose another slug."

    if [ -z "$TITLE" ]; then
        default_title="$(printf '%s' "$SLUG" | tr '-' ' ' | awk '{ for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2) } 1')"
        if [ -t 0 ]; then
            read -r -p "Subsite title [$default_title]: " TITLE
        fi
        TITLE="${TITLE:-$default_title}"
    fi

    create_args=(--slug="$SLUG" --title="$TITLE" --porcelain)
    [ -n "$EMAIL" ] && create_args+=(--email="$EMAIL")

    echo "Creating /$SLUG/"
    blog_id="$(site_wp site create "${create_args[@]}")"
    SUBSITE_URL="$(site_wp site list --site__in="$blog_id" --field=url)"
fi

# ---------------------------------------------------------------------------
# 2. Link folders for every subsite
# ---------------------------------------------------------------------------

TARGETS=(
    wp-admin wp-includes wp-content
    wp-login.php wp-signup.php wp-activate.php wp-cron.php
    wp-comments-post.php wp-trackback.php wp-links-opml.php wp-mail.php
    xmlrpc.php
)

# One path per subsite, e.g. "/news/". The main site ("/") is skipped.
# Uses WP-CLI through Studio, so it works with SQLite and MySQL alike.
PATHS=$(site_wp site list --field=path 2>/dev/null | grep -E '^/[_0-9a-zA-Z-]+/$' || true)

if [ -z "$PATHS" ]; then
    echo "No subdirectory subsites found (is this a subdirectory network?)."
    exit 0
fi

for p in $PATHS; do
    slug="${p#/}"
    slug="${slug%/}"

    if taken "$slug"; then
        echo "Skipping /$slug/: a file or folder with that name already exists, so its /wp-admin/ won't work."
        continue
    fi

    new=false
    [ -d "$slug" ] || new=true
    mkdir -p "$slug"
    touch "$slug/.studio-subsite-links"
    for t in "${TARGETS[@]}"; do
        ln -sfn "../$t" "$slug/$t"
    done

    # Keep the link folders out of git when the site is in a repo.
    if [ -d .git/info ] && ! grep -qx "/$slug/" .git/info/exclude 2>/dev/null; then
        echo "/$slug/" >> .git/info/exclude
    fi

    [ "$new" = true ] && echo "Linked /$slug/"
done

if [ "$LINKS_ONLY" = false ]; then
    echo
    echo "Subsite:  ${SUBSITE_URL%/}/"
    echo "Admin:    ${SUBSITE_URL%/}/wp-admin/"
fi
