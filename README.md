# Studio Installer

Creates a local WordPress site with [WordPress Studio](https://developer.wordpress.com/studio/)
by asking a few questions: single site or multisite, Studio's SQLite database or MySQL in Docker,
domain, HTTPS, PHP and WordPress versions, and the admin login.

## Requirements

- macOS
- WordPress Studio with its CLI enabled (Studio > Settings), tested with CLI 2.2.0
- Docker Desktop, only for the MySQL option

## Get started

**To keep your own copy** (for example to change the defaults or the templates), click
**Use this template** at the top of this repo's GitHub page, create your repo, then clone it:

```bash
git clone https://github.com/<you>/<your-repo>.git
cd <your-repo>
./install.sh
```

A template copy starts with fresh history and doesn't get later changes automatically. To pull
them in, add this repo as a remote and merge from it:

```bash
git remote add upstream https://github.com/troychaplin/studio-installer.git
git fetch upstream
git merge upstream/main --allow-unrelated-histories
```

**To just run it**, clone this repo:

```bash
git clone https://github.com/troychaplin/studio-installer.git
cd studio-installer
./install.sh
```

The installer creates each site in its own folder (`~/Studio/<slug>` by default), not inside
this repo, so one copy can create as many sites as you like.

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
