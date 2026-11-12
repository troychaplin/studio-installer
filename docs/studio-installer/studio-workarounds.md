# Studio workarounds

WordPress Studio is built for single sites on its own SQLite database. Each item below is a place
where the installer steers around Studio's behaviour, with the reason and where the fix lives.
Tested with Studio CLI 2.2.0.

## Multisite

### Subsite `/wp-admin/` redirect loop

- **Problem:** Studio serves sites with PHP's built-in server and its own router, which
  **ignores `.htaccess`**. Apache uses the multisite rewrites to map `/<slug>/wp-admin/`,
  `/<slug>/wp-includes/`, `/<slug>/wp-content/` and `/<slug>/wp-*.php` to the real files at the
  root. Studio's router only runs a file if one exists at the exact path, and sends everything
  else to `index.php`. WordPress then redirects the request to itself, in a loop.
- **Fix:** `scripts/add-subsite.sh` creates the subsite, then a `<slug>/` folder in the site root
  for each subsite. The folder holds symlinks to `wp-admin`, `wp-includes`, `wp-content` and the `wp-*.php`
  entry points, so the router finds real files. It has no `index.php`, so subsite pages still go
  through WordPress.
  - It gets subsites from `studio wp site list`, so it also links subsites created elsewhere.
    **After creating a subsite in the network admin, run it with `--links-only`.**
  - It refuses a new slug that matches a real file or folder in the site root (such as `docs` or
    `scripts`), and skips existing subsites with such a slug.
  - If the site folder is a git repo, the script adds the folders to `.git/info/exclude`.

### Studio's localhost requests (custom domain only)

- **Problem:** Studio's server calls itself at `http://localhost:<port>`, for example to set the
  admin login during startup. A network looks the site up by host name. On a custom domain it
  doesn't recognise `localhost:<port>` and answers with a redirect, so Studio's request fails. In
  the project this installer came from, that stopped the site from starting ("PHP error during
  startup"; the daemon log says `Failed to set admin credentials: fetch failed`).
- **Fix:** `scripts/templates/wp-config-multisite.php` rewrites `HTTP_HOST` from `localhost` or
  `127.0.0.1` (any port) to `DOMAIN_CURRENT_SITE`. The installer inserts it into `wp-config.php`
  after converting to multisite. Browser traffic uses the custom domain, so only Studio's own
  requests are affected.
- A multisite without a custom domain uses `localhost:<port>` as its network domain, so it doesn't
  need this.

### Subdomain networks don't work

Studio's proxy routes only the site's own domain, and its hosts entry and certificate cover only
that name. In testing, a subsite at `news.<domain>.local` returned 404 from the proxy over HTTP
and failed the TLS handshake over HTTPS, even with the name pointed at `127.0.0.1`. The installer
therefore offers subdirectory networks only and rejects `--type=subdomain`.

## Studio CLI quirks

### Only empty folders or existing WordPress

`studio create` stops with "The selected directory is not empty nor an existing WordPress site"
for a folder that has other files in it, such as this repo. The installer stages WordPress in a
temporary folder first; see [setup.md](setup.md).

### `studio delete` trashes the whole folder

`studio delete` moves the site's entire folder to the trash by default. For a site installed in
the repo folder that includes `scripts/` and `.git`, so use `studio delete --no-files` there.

### Its own prompts

In an interactive terminal, `studio create` can ask "Site path:" and suggest `~/Studio/<name>`
even when `--path` is given. The installer runs it with stdin from `/dev/null`, so Studio skips
its prompts and uses the flags.

### HTTPS certificate isn't trusted on macOS

Studio signs `https://*.local` with its own root certificate,
`~/.studio/certificates/studio-ca.crt`. On macOS only the Studio app adds it to the trust store;
the CLI doesn't. The installer trusts it in the login keychain:

```bash
security add-trusted-cert -r trustRoot -p ssl -k ~/Library/Keychains/login.keychain-db ~/.studio/certificates/studio-ca.crt
```

Firefox has its own certificate store and may still need you to accept it once.

### Ports 80 and 443

Studio's proxy listens on ports 80 and 443 for sites with a custom domain. Any other local server
on those ports (for example a Traefik or Caddy Docker stack) can't run at the same time. The
site's own PHP server runs on a port Studio picks (8881 and up); there's no option to choose it.

### Admin password is reset on every start

Studio stores the admin login from `studio create` and applies it on every start. If you change
the password in WordPress, Studio puts its stored one back at the next start. To change it, use
`studio config set --admin-password=…`.

## Files Studio writes

| File | What Studio does |
|---|---|
| `wp-config.php` | Created with the site. Studio adds the debug constants it manages when they're missing. |
| `wp-content/db.php`, `wp-content/mu-plugins/sqlite-database-integration/` | The SQLite drop-in. Installed or updated on start while any SQLite piece is present. |
| `wp-content/database/.ht.sqlite` | The live SQLite database. |
| `wp-content/mu-plugins/99-studio-loader.php` | Written on start; loads Studio's own mu-plugins from `~/.studio/mu-plugins/<id>/`. |
| `STUDIO.md`, `AGENTS.md`, `CLAUDE.md`, `.agents/`, `.claude/` | AI instruction files, written at site creation. |
| `/etc/hosts`, `~/.studio/certificates/domains/` | Hosts entry and certificate for a custom domain. |
