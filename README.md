# Studio Installer

Creates a local WordPress site with [WordPress Studio](https://developer.wordpress.com/studio/)
by asking a few questions: single site or multisite, Studio's SQLite database or MySQL in Docker,
domain, HTTPS, PHP and WordPress versions, and the admin login.

## Requirements

- macOS
- WordPress Studio with its CLI enabled (Studio > Settings), tested with CLI 2.2.0
- Docker Desktop, only for the MySQL option

## Get started

There are two ways to use this repo. Either way, the installer creates each site in its own
folder (`~/Studio/<slug>` by default), not inside the repo, so one copy can create as many sites
as you like.

| | Use as a template | Clone this repo |
|---|---|---|
| Best for | Changing the installer for yourself or your team | Running it as it is |
| You get | Your own repo, with fresh history | A copy of this repo |
| Updates | Merge them in yourself (see below) | `git pull` |

### Use as a template

1. On this repo's GitHub page, click **Use this template** > **Create a new repository**.
2. Choose an owner (you or your organisation) and a name, pick public or private, and click
   **Create repository**.
3. Clone your new repo and run the installer:

   ```bash
   git clone https://github.com/<owner>/<your-repo>.git
   cd <your-repo>
   ./install.sh
   ```

Or do all three steps with the [GitHub CLI](https://cli.github.com/):

```bash
gh repo create <your-repo> --template troychaplin/studio-installer --private --clone
cd <your-repo>
./install.sh
```

Things you might change in your copy:

- The defaults in the "Questions" section of `install.sh` (PHP version, admin username and
  email, and so on), and `MYSQL_IMAGE` and `MYSQL_FIRST_PORT` at the top.
- `templates/docker-compose.yml`, for example to add phpMyAdmin or Mailpit.
- `templates/wp-config-multisite.php`, for extra constants on multisite.

### Get updates from this template

A repo made from a template doesn't share history with it, so GitHub won't offer updates. Pull
them in with git instead.

**Connect your repo to this one once, right after creating it and before you change anything.**
Add this repo as a remote called `upstream` and merge it. Nothing changes in your files; the merge
only records where your copy started, so later updates merge cleanly:

```bash
git remote add upstream https://github.com/troychaplin/studio-installer.git
git fetch upstream
git merge upstream/main --allow-unrelated-histories -m "Connect to studio-installer template"
git push
```

`--allow-unrelated-histories` is needed for this first merge only. If you've already changed
files before connecting, the first merge reports a conflict in every file you changed, even
where this repo hasn't touched it; keep your version of each.

After that, update with:

```bash
git fetch upstream
git merge upstream/main
```

If you've changed a file that was also changed here, git stops with a conflict in that file.
Edit it to keep the parts you want, then `git add` it and `git commit`. Push to your own repo
with `git push` as usual.

### Clone this repo

```bash
git clone https://github.com/troychaplin/studio-installer.git
cd studio-installer
./install.sh
```

Get updates with `git pull`.

## Usage

```bash
./install.sh
```

Press Enter to accept a default. Every question also has a flag, and `--yes` skips the questions:

```bash
./install.sh --yes --name="My Network" --type=multisite --domain=my-network.local
```

| Question | Flag | Default |
|---|---|---|
| Site name | `--name=` | `My Site` |
| Site folder (missing or empty) | `--path=` | `~/Studio/<slug>` |
| Single site or multisite | `--type=single\|multisite` | `single` |
| Custom domain, or `none` for `http://localhost:<port>` | `--domain=` | `<slug>.local` |
| HTTPS (custom domain only) | `--https` / `--no-https` | on |
| PHP version | `--php=8.2\|8.3\|8.4\|8.5` | `8.4` |
| WordPress version | `--wp=` | `auto-update` |
| Database | `--db=sqlite\|mysql` | `sqlite` |
| MySQL host port | `--db-port=` | first free port from 3381 |
| Admin username, email, password | `--admin-user=`, `--admin-email=`, `--admin-password=` | `admin`, `admin@localhost.com`, generated |

Multisite is subdirectory only. Subdomain networks can't be served by Studio; see
[docs/studio-workarounds.md](docs/studio-workarounds.md).

## After adding a subsite

Studio needs a folder of symlinks per subsite for its `/wp-admin/` to work:

```bash
scripts/subsite-links.sh --path=<site folder>
```

## More

- [docs/setup.md](docs/setup.md): what the installer does, step by step
- [docs/studio-workarounds.md](docs/studio-workarounds.md): where it steers around Studio's behaviour, and why
- [docs/docker-mysql.md](docs/docker-mysql.md): the MySQL option

## License

[MIT](LICENSE)
