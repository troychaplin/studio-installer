# How the installer works

`install.sh` creates a new Studio site, by default in the folder that holds `install.sh`, so the
repo becomes the site. It can also use any new or empty folder. Studio copies WordPress in; the
installer then adjusts the database and multisite setup to match your answers. The questions
and flags are listed in the [README](../README.md).

## The steps

1. **Checks.** macOS and the `studio` CLI are required. The script's own folder must not already
   have WordPress in it (`wp-load.php`, `wp-config.php` or `wp-content/`); any other folder must
   be missing or empty. The folder must not already be a Studio site, and the domain must end in
   `.local` and not belong to another Studio site. For MySQL, Docker must
   be running and the port free. Nothing is created until these pass and you confirm the summary.
2. **Studio site.** Runs `studio create` with the name, folder, PHP and WordPress versions, admin
   login, and the domain and HTTPS if chosen. Studio installs WordPress on SQLite and starts the
   site. stdin comes from `/dev/null` so Studio doesn't ask its own questions.
   - Studio refuses a folder that has files but no WordPress, which is the case for the repo
     folder. So the installer first has Studio set WordPress up in an empty temporary folder,
     removes that temporary site from Studio, moves the files into the repo folder, and then
     creates the real site there. Studio's AI files (`STUDIO.md`, `AGENTS.md`, `CLAUDE.md`,
     `.agents/`, `.claude/`) aren't moved; Studio writes them again for the real site and keeps
     any you already have.
   - With a custom domain, Studio asks for your macOS password to add it to `/etc/hosts`.
   - With MySQL, the site is created but not started yet.
3. **MySQL (optional).** See [docker-mysql.md](docker-mysql.md).
4. **Multisite (optional).** Runs `studio wp core multisite-convert`, which creates the network
   tables and adds the multisite constants to `wp-config.php`. With a custom domain, the installer
   then stops the site, inserts `templates/wp-config-multisite.php` above the "stop editing" line,
   and starts it again. See [studio-workarounds.md](studio-workarounds.md) for why.
5. **HTTPS certificate (HTTPS only).** Trusts Studio's root certificate in the macOS login
   keychain if it isn't trusted yet. macOS asks for your password.
6. **Done.** Prints the site, admin and network URLs and the login.

If a step fails after the site is created, the installer prints the commands to remove it.

## Templates

| File | Used for |
|---|---|
| `templates/docker-compose.yml` | Copied to the site folder for MySQL, with the project name, container name, image and port filled in. |
| `templates/wp-config-multisite.php` | Inserted into `wp-config.php` for a multisite on a custom domain. |

## The admin login

The username, email and password are passed to Studio, which **sets that password on the user
every time the site starts**. To change it, use `studio config set --admin-password=…` in the site
folder. A password passed with `--admin-password` is visible in the process list while the
installer runs; leave it out to be asked for it, or to have one generated.

## After setup

- WP-CLI: `studio wp <command>` in the site folder. For a subsite, add `--url=<subsite URL>`.
- Add subsites with `scripts/add-subsite.sh --slug=<slug>`, which creates the subsite and its
  link folder. After creating one in the network admin, run `scripts/add-subsite.sh --links-only`.
- Change Studio settings with `studio config set` (`--php`, `--xdebug`, `--admin-password`, …).
  Don't change the domain of a multisite: the network's domain is stored in its database and
  `wp-config.php`.
- Remove a site in the script's folder with `studio delete --no-files` (without `--no-files`
  Studio trashes the whole folder, repo included), then `git clean -fdX` to remove the ignored
  WordPress files. Preview with `git clean -ndX` first. A site in its own folder can be removed
  with `studio delete --path=<site folder>`. For MySQL, also run
  `docker compose -p <slug>-studio down -v` to remove the container and its data.

## What git tracks in a site folder

`.gitignore` ignores WordPress core, `wp-config.php`, everything in `wp-content/` except
`themes/`, `plugins/` and `mu-plugins/`, the default themes and plugins, Studio's SQLite drop-in
and loader, Studio's AI files, and the generated `docker-compose.yml`. Your own themes, plugins
and mu-plugins show up in `git status` and can be committed. Subsite link folders are added to
`.git/info/exclude` by `scripts/add-subsite.sh`.
