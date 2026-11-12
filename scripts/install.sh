#!/bin/bash

# Creates a local WordPress site with WordPress Studio, asking a few questions
# first: single site or multisite, Studio's SQLite database or MySQL in Docker,
# domain, HTTPS, PHP and WordPress versions, and the admin login.
#
# Every question has a flag. Anything not given as a flag is asked, or takes
# its default with --yes.
#
# Usage: scripts/install.sh [options]
#
#   --name=<name>            Site name                      (default: My Site)
#   --path=<folder>          Site folder: the repo folder (the one above scripts/),
#                            or a missing or empty one      (default: the repo folder)
#   --type=<type>            single | multisite (subdirectories)   (default: single)
#   --domain=<name.local>    Custom domain, or "none" for http://localhost:<port>
#                                                           (default: <slug>.local)
#   --https | --no-https     HTTPS on the custom domain     (default: on)
#   --php=<version>          8.2 | 8.3 | 8.4 | 8.5          (default: 8.4)
#   --wp=<version>           auto-update, or a version such as 6.8   (default: auto-update)
#   --db=<db>                sqlite | mysql (MySQL runs in Docker)   (default: sqlite)
#   --db-port=<port>         Host port for MySQL            (default: first free from 3381)
#   --admin-user=<name>      Admin username                 (default: admin)
#   --admin-email=<email>    Admin email                    (default: admin@localhost.com)
#   --admin-password=<pass>  Admin password                 (default: generated)
#   --yes                    Don't ask anything; use flags and defaults
#   -h, --help               Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# The repo folder, above scripts/. WordPress goes here by default.
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES="$SCRIPT_DIR/templates"

MYSQL_IMAGE="mysql:8.4"
MYSQL_FIRST_PORT=3381

NAME="" SITE_PATH="" TYPE="" DOMAIN="" HTTPS="" PHP="" WP="" DB="" DB_PORT=""
ADMIN_USER="" ADMIN_EMAIL="" ADMIN_PASSWORD=""
YES=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

step() { printf '\n==> %s\n' "$1"; }
fail() { echo "Error: $1" >&2; exit 1; }

require() {
    command -v "$1" >/dev/null 2>&1 || fail "'$1' is not installed. $2"
}

slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# ask VAR "Question" "default"
# Keeps a value given as a flag. With --yes, takes the default.
ask() {
    local var="$1" question="$2" default="$3" answer
    [ -n "${!var}" ] && return
    if [ "$YES" = true ]; then
        printf -v "$var" '%s' "$default"
        return
    fi
    read -r -p "$question [$default]: " answer
    printf -v "$var" '%s' "${answer:-$default}"
}

# choose VAR "Question" DEFAULT_NUMBER "value|Label" "value|Label" ...
choose() {
    local var="$1" question="$2" default="$3" i=1 opt answer
    shift 3
    [ -n "${!var}" ] && return
    if [ "$YES" = true ]; then
        opt="${!default}"
        printf -v "$var" '%s' "${opt%%|*}"
        return
    fi
    printf '\n%s\n' "$question"
    for opt in "$@"; do
        printf '  %d) %s\n' "$i" "${opt#*|}"
        i=$((i + 1))
    done
    while true; do
        read -r -p "Choose [$default]: " answer
        answer="${answer:-$default}"
        if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le "$#" ]; then
            opt="${!answer}"
            printf -v "$var" '%s' "${opt%%|*}"
            return
        fi
        echo "Enter a number from 1 to $#."
    done
}

one_of() {
    local value="$1" option
    shift
    for option in "$@"; do [ "$value" = "$option" ] && return 0; done
    return 1
}

port_in_use() { nc -z 127.0.0.1 "$1" >/dev/null 2>&1; }

free_port() {
    local port="$1"
    while port_in_use "$port"; do port=$((port + 1)); done
    echo "$port"
}

# Runs WP-CLI against the new site.
site_wp() { studio wp --path="$SITE_PATH" "$@"; }

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------

for arg in "$@"; do
    case "$arg" in
        --name=*)           NAME="${arg#*=}" ;;
        --path=*)           SITE_PATH="${arg#*=}" ;;
        --type=*)           TYPE="${arg#*=}" ;;
        --domain=*)         DOMAIN="${arg#*=}" ;;
        --https)            HTTPS="yes" ;;
        --no-https)         HTTPS="no" ;;
        --php=*)            PHP="${arg#*=}" ;;
        --wp=*)             WP="${arg#*=}" ;;
        --db=*)             DB="${arg#*=}" ;;
        --db-port=*)        DB_PORT="${arg#*=}" ;;
        --admin-user=*)     ADMIN_USER="${arg#*=}" ;;
        --admin-email=*)    ADMIN_EMAIL="${arg#*=}" ;;
        --admin-password=*) ADMIN_PASSWORD="${arg#*=}" ;;
        --yes|-y)           YES=true ;;
        -h|--help)          sed -n '3,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)                  fail "Unknown option: $arg (see --help)" ;;
    esac
done

if [ "$YES" = false ] && [ ! -t 0 ]; then
    fail "No terminal to ask questions in. Pass --yes to use flags and defaults."
fi

[ "$(uname)" = "Darwin" ] || fail "This installer supports macOS only."
require studio "Install WordPress Studio and enable its CLI (Studio > Settings)."

# ---------------------------------------------------------------------------
# Questions
# ---------------------------------------------------------------------------

ask NAME "Site name" "My Site"
SLUG="$(slugify "$NAME")"
[ -n "$SLUG" ] || fail "The site name needs at least one letter or number."

ask SITE_PATH "Site folder" "$ROOT_DIR"
case "$SITE_PATH" in
    "~")   SITE_PATH="$HOME" ;;
    "~/"*) SITE_PATH="$HOME/${SITE_PATH#\~/}" ;;
    /*)    ;;
    *)     SITE_PATH="$PWD/$SITE_PATH" ;;
esac
SITE_PATH="${SITE_PATH%/}"

choose TYPE "Site type" 1 "single|Single site" "multisite|Multisite with subdirectories (example.local/news/)"
[ "$TYPE" = "subdirectory" ] && TYPE="multisite"
# Studio only routes and certifies the site's own domain, so subsites on
# subdomains can't be reached. See docs/studio-installer/studio-workarounds.md.
[ "$TYPE" = "subdomain" ] && fail "Subdomain networks don't work in Studio (see docs/studio-installer/studio-workarounds.md). Use --type=multisite."
one_of "$TYPE" single multisite || fail "--type must be single or multisite."

ask DOMAIN "Custom domain (must end in .local), or 'none' for http://localhost:<port>" "$SLUG.local"
DOMAIN="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')"
if [ "$DOMAIN" = "none" ]; then
    DOMAIN=""
    HTTPS="no"
elif [[ ! "$DOMAIN" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.local$ ]]; then
    fail "'$DOMAIN' isn't a valid domain. Studio needs one that ends in .local, such as $SLUG.local."
fi

if [ -n "$DOMAIN" ]; then
    choose HTTPS "Use HTTPS?" 1 "yes|Yes" "no|No"
fi
one_of "$HTTPS" yes no || fail "HTTPS must be yes or no."

choose PHP "PHP version" 3 "8.2|8.2" "8.3|8.3" "8.4|8.4" "8.5|8.5"
one_of "$PHP" 8.2 8.3 8.4 8.5 || fail "--php must be 8.2, 8.3, 8.4 or 8.5."

ask WP "WordPress version ('auto-update' for the latest, or a version such as 6.8)" "auto-update"

choose DB "Database" 1 "sqlite|Studio's built-in SQLite" "mysql|MySQL in a Docker container"
one_of "$DB" sqlite mysql || fail "--db must be sqlite or mysql."

if [ "$DB" = "mysql" ]; then
    ask DB_PORT "MySQL port on this computer" "$(free_port "$MYSQL_FIRST_PORT")"
    [[ "$DB_PORT" =~ ^[0-9]+$ ]] || fail "The MySQL port must be a number."
fi

ask ADMIN_USER "Admin username" "admin"
ask ADMIN_EMAIL "Admin email" "admin@localhost.com"
if [ -z "$ADMIN_PASSWORD" ] && [ "$YES" = false ]; then
    read -r -s -p "Admin password [leave empty to generate one]: " ADMIN_PASSWORD
    echo
fi
PASSWORD_GENERATED=false
if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)"
    PASSWORD_GENERATED=true
fi

if [ -n "$DOMAIN" ]; then
    [ "$HTTPS" = "yes" ] && SITE_URL="https://$DOMAIN" || SITE_URL="http://$DOMAIN"
else
    SITE_URL="http://localhost:<port chosen by Studio>"
fi

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

# The repo folder may hold the installer's files (and anything else
# you keep in your copy of the repo), but not WordPress. Any other folder must
# be missing or empty.
IN_REPO=false
if [ -d "$SITE_PATH" ] && [ "$(cd "$SITE_PATH" && pwd -P)" = "$(cd "$ROOT_DIR" && pwd -P)" ]; then
    IN_REPO=true
    for f in wp-load.php wp-config.php wp-content; do
        [ -e "$SITE_PATH/$f" ] && fail "$SITE_PATH already has WordPress in it ($f). This installer is for a new site."
    done
elif [ -e "$SITE_PATH" ]; then
    [ -d "$SITE_PATH" ] || fail "$SITE_PATH exists and isn't a folder."
    [ -z "$(ls -A "$SITE_PATH")" ] || fail "$SITE_PATH isn't empty. Choose the repo folder ($ROOT_DIR), or a new or empty one."
fi

SITES_JSON="$(studio list --format json 2>/dev/null | grep '^\[' || true)"
if printf '%s' "$SITES_JSON" | grep -qF "\"path\":\"$SITE_PATH\""; then
    fail "$SITE_PATH is already a Studio site."
fi
if [ -n "$DOMAIN" ] && printf '%s' "$SITES_JSON" | grep -qF "\"customDomain\":\"$DOMAIN\""; then
    fail "Another Studio site already uses $DOMAIN."
fi

if [ "$DB" = "mysql" ]; then
    require docker "Install Docker Desktop, or choose the SQLite database."
    docker info >/dev/null 2>&1 || fail "Docker isn't running. Start Docker Desktop, then run this again."
    port_in_use "$DB_PORT" && fail "Port $DB_PORT is already in use. Pass another with --db-port."
    [ -f "$TEMPLATES/docker-compose.yml" ] || fail "$TEMPLATES/docker-compose.yml is missing."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

[ "$TYPE" = "multisite" ] && type_label="Multisite, subdirectories" || type_label="Single site"
[ "$DB" = "mysql" ] && db_label="MySQL in Docker ($MYSQL_IMAGE, port $DB_PORT)" || db_label="Studio SQLite"

printf '\n'
printf '  Name:       %s\n' "$NAME"
printf '  Folder:     %s\n' "$SITE_PATH"
printf '  Type:       %s\n' "$type_label"
printf '  URL:        %s\n' "$SITE_URL"
printf '  PHP:        %s\n' "$PHP"
printf '  WordPress:  %s\n' "$WP"
printf '  Database:   %s\n' "$db_label"
printf '  Admin:      %s <%s>\n' "$ADMIN_USER" "$ADMIN_EMAIL"

if [ "$YES" = false ]; then
    printf '\n'
    read -r -p "Create this site? [Y/n]: " answer
    case "$answer" in
        ""|y|Y|yes|Yes) ;;
        *) echo "Nothing was created."; exit 0 ;;
    esac
fi

# From here on a failure can leave a half-made site behind. Say how to remove it.
CREATED=false
STAGE=""
on_exit() {
    [ "$?" -ne 0 ] || return 0
    # A leftover staging site is only ever a temporary folder; remove it.
    if [ -n "$STAGE" ] && [ -d "$STAGE" ]; then
        studio delete --path="$STAGE" >/dev/null 2>&1 || true
        rm -rf "$STAGE"
    fi
    [ "$CREATED" = true ] || return 0
    echo
    echo "Setup stopped before it finished. To remove the half-made site:"
    if [ "$IN_REPO" = true ]; then
        # Without --no-files Studio would move this whole folder to the trash,
        # including scripts/ and .git.
        echo "  studio delete --path=\"$SITE_PATH\" --no-files"
        echo "  git -C \"$SITE_PATH\" clean -fdX    # removes WordPress; preview with -ndX first"
    else
        echo "  studio delete --path=\"$SITE_PATH\""
    fi
    [ "$DB" = "mysql" ] && echo "  docker compose -p \"$SLUG-studio\" down -v"
    return 0
}
trap on_exit EXIT

# ---------------------------------------------------------------------------
# 1. Studio site
# ---------------------------------------------------------------------------

step "Studio site"
mkdir -p "$SITE_PATH"

# Studio only creates a site in an empty folder or one that already holds
# WordPress. For the repo folder, let Studio set WordPress up in an empty
# temporary folder first, move it in, and forget the temporary site.
if [ "$IN_REPO" = true ]; then
    STAGE="$(mktemp -d "${TMPDIR:-/tmp}/studio-installer.XXXXXX")"
    echo "Preparing WordPress in a temporary folder"
    CREATED=true
    studio create --path="$STAGE" --name="$NAME (temporary)" --php="$PHP" --wp="$WP" \
        --start=false --skip-browser --skip-log-details </dev/null >/dev/null
    studio delete --path="$STAGE" --no-files >/dev/null
    # Studio writes its AI instruction files again for the real site, and
    # doesn't replace ones you already have.
    for f in "$STAGE"/* "$STAGE"/.[!.]*; do
        [ -e "$f" ] || continue
        case "$(basename "$f")" in
            STUDIO.md|AGENTS.md|CLAUDE.md|.agents|.claude) continue ;;
        esac
        mv "$f" "$SITE_PATH/"
    done
    rm -rf "$STAGE"
    STAGE=""
fi

create_args=(
    --path="$SITE_PATH"
    --name="$NAME"
    --php="$PHP"
    --wp="$WP"
    --admin-username="$ADMIN_USER"
    --admin-email="$ADMIN_EMAIL"
    --admin-password="$ADMIN_PASSWORD"
    --skip-browser
    --skip-log-details
)
[ -n "$DOMAIN" ] && create_args+=(--domain="$DOMAIN")
[ "$HTTPS" = "yes" ] && create_args+=(--https)
# With MySQL the site must not start until the database is switched over.
[ "$DB" = "mysql" ] && create_args+=(--start=false)

[ -n "$DOMAIN" ] && echo "Studio may ask for your macOS password to add $DOMAIN to /etc/hosts."
CREATED=true
# </dev/null: in a terminal Studio asks "Site path:" again. Without a terminal
# on stdin it skips its prompts and uses the flags.
studio create "${create_args[@]}" </dev/null

# ---------------------------------------------------------------------------
# 2. MySQL in Docker
# ---------------------------------------------------------------------------

if [ "$DB" = "mysql" ]; then
    step "MySQL in Docker"

    # Compose identifies a stack by its project name, so the project, the
    # container and the port all have to be unique to this site.
    sed -e "s|{{PROJECT}}|$SLUG-studio|g" \
        -e "s|{{CONTAINER}}|$SLUG-studio-mysql|g" \
        -e "s|{{IMAGE}}|$MYSQL_IMAGE|g" \
        -e "s|{{PORT}}|$DB_PORT|g" \
        "$TEMPLATES/docker-compose.yml" > "$SITE_PATH/docker-compose.yml"
    (cd "$SITE_PATH" && docker compose up -d --wait --quiet-pull)

    # Studio puts SQLite back on every start while any of these exist.
    rm -rf "$SITE_PATH/wp-content/db.php" \
           "$SITE_PATH/wp-content/database" \
           "$SITE_PATH/wp-content/mu-plugins/sqlite-database-integration"

    # A site that hasn't started has no wp-config.php yet. Studio keeps a site
    # on MySQL when one exists and the SQLite pieces are gone, and installs
    # WordPress into it on first start. Studio forces DB_NAME to "wordpress";
    # the container creates that database.
    site_wp config create --force --skip-check --dbname=wordpress --dbuser=wp --dbpass=wp \
        --dbhost="127.0.0.1:$DB_PORT"

    studio start --path="$SITE_PATH" --skip-browser --skip-log-details
fi

# The real URL: Studio picks the port when there's no custom domain.
STATUS_JSON="$(studio status --path="$SITE_PATH" --format json 2>/dev/null || true)"
url="$(printf '%s' "$STATUS_JSON" | sed -n 's/.*"siteUrl": *"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "$url" ] && SITE_URL="${url%/}"
case "$SITE_URL" in http*://*"<"*) fail "Couldn't read the site's URL from 'studio status'." ;; esac

if [ "$DB" = "mysql" ] && ! site_wp core is-installed >/dev/null 2>&1; then
    echo "Installing WordPress into MySQL"
    site_wp core install --url="$SITE_URL" --title="$NAME" --admin_user="$ADMIN_USER" \
        --admin_email="$ADMIN_EMAIL" --admin_password="$ADMIN_PASSWORD" --skip-email
fi

# ---------------------------------------------------------------------------
# 3. Multisite
# ---------------------------------------------------------------------------

if [ "$TYPE" != "single" ]; then
    step "Multisite"
    site_wp core multisite-convert --title="$NAME"

    if [ -n "$DOMAIN" ]; then
        # Studio's own startup requests arrive as localhost:<port>. A network
        # doesn't know that host and redirects, which stops the site starting.
        # The snippet maps those requests to the network's domain.
        config="$SITE_PATH/wp-config.php"
        marker="/\* That's all, stop editing"
        grep -q "$marker" "$config" || fail "Couldn't find the 'stop editing' line in wp-config.php."
        studio stop --path="$SITE_PATH"
        awk -v snippet="$TEMPLATES/wp-config-multisite.php" -v marker="$marker" '
            $0 ~ marker { while ((getline line < snippet) > 0) if (line !~ /^<\?php/) print line; print "" }
            { print }
        ' "$config" > "$config.tmp"
        mv "$config.tmp" "$config"
        studio start --path="$SITE_PATH" --skip-browser --skip-log-details
    fi
fi

# ---------------------------------------------------------------------------
# 4. HTTPS certificate
# ---------------------------------------------------------------------------

# Studio signs https://*.local with its own root certificate. Its CLI doesn't
# add that certificate to the macOS trust store (only the Studio app does), so
# browsers reject the site until it's trusted.
if [ "$HTTPS" = "yes" ]; then
    step "HTTPS certificate"
    STUDIO_CA="$HOME/.studio/certificates/studio-ca.crt"
    if [ ! -f "$STUDIO_CA" ]; then
        echo "Warning: $STUDIO_CA not found; skipping. Browsers may show a certificate error."
    elif security verify-cert -c "$STUDIO_CA" -p ssl -l >/dev/null 2>&1; then
        echo "Studio's certificate is already trusted."
    else
        echo "Trusting Studio's certificate (macOS will ask for your password)..."
        security add-trusted-cert -r trustRoot -p ssl -k "$HOME/Library/Keychains/login.keychain-db" "$STUDIO_CA"
        echo "Trusted. Restart your browser if it still shows a certificate error."
    fi
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

trap - EXIT
step "Done"
echo "Site:      $SITE_URL"
echo "Admin:     $SITE_URL/wp-admin/"
[ "$TYPE" != "single" ] && echo "Network:   $SITE_URL/wp-admin/network/"
echo "Username:  $ADMIN_USER"
if [ "$PASSWORD_GENERATED" = true ]; then
    echo "Password:  $ADMIN_PASSWORD"
else
    echo "Password:  the one you entered"
fi
echo "Folder:    $SITE_PATH"
if [ "$DB" = "mysql" ]; then
    echo "MySQL:     127.0.0.1:$DB_PORT, database 'wordpress', user 'wp', password 'wp'"
    echo "           Start and stop it from the site folder with: docker compose up -d / docker compose stop"
fi
if [ "$TYPE" = "multisite" ]; then
    echo
    echo "Add subsites with this, so their /wp-admin/ works in Studio:"
    if [ "$IN_REPO" = true ]; then
        echo "  scripts/add-subsite.sh --slug=<slug>"
    else
        echo "  $SCRIPT_DIR/add-subsite.sh --slug=<slug> --path=\"$SITE_PATH\""
    fi
    echo "For subsites made in the network admin, run it with --links-only afterwards."
fi
if [ "$IN_REPO" = true ]; then
    echo
    echo "To remove this site later, keep its files out of Studio's delete:"
    echo "  studio delete --path=\"$SITE_PATH\" --no-files"
    echo "  git clean -fdX    # removes WordPress and the database; preview with -ndX first"
fi
