# step CLI Bootstrap

Installs the [smallstep `step` CLI](https://smallstep.com/docs/step-cli/) on Debian-based systems
and can bootstrap the host to a [step-ca](https://smallstep.com/docs/step-ca/) right away (download
and verify the root certificate, optionally add it to the system trust store).

Supported: **Debian, Ubuntu, Raspberry Pi OS (32/64 bit, incl. ARMv6) and DietPi**.

To roll it out to many hosts over SSH use
[ssh-step-cli-bootstrap-manager](https://github.com/Michdo93/ssh-step-cli-bootstrap-manager).

## Quick start

As root or as a user with `sudo` (works with `| sh` and `| bash`):

```bash
wget -qO- https://raw.githubusercontent.com/Michdo93/step-cli-bootstrap/main/install.sh | sh
# or
curl -fsSL https://raw.githubusercontent.com/Michdo93/step-cli-bootstrap/main/install.sh | sh
```

The script asks whether it should bootstrap to a step-ca. Press Enter to only install `step`.

Without questions:

```bash
wget -qO- https://raw.githubusercontent.com/Michdo93/step-cli-bootstrap/main/install.sh \
  | sh -s -- --ca-url https://ca.lab:9000 --fingerprint <sha256> --trust --yes
```

## What it does

1. **Privileges:** runs as root or prefixes the administrative commands with `sudo` (the sudo
   password is asked once). Without a terminal, sudo must work without a password.
2. **OS check:** Debian, Ubuntu, Raspberry Pi OS, DietPi (other apt-based systems with a warning).
3. **Installation:**
   - amd64, arm64, armhf (ARMv7): the official smallstep apt repository
     (`/etc/apt/keyrings/smallstep.asc`, `/etc/apt/sources.list.d/smallstep.sources`) – updates
     then come with `apt upgrade`.
   - ARMv6 (Raspberry Pi 1 / Zero): the ARMv6 release binary to `/usr/local/bin/step` (the armhf
     package would not run there).
   - If the repository fails, the release binary is used as a fallback and the repository entry
     is removed again, so that `apt-get update` keeps working.
   - `apt` never stops at "configuration file modified" questions (`--force-confdef/--force-confold`).
4. **Optional bootstrap:** `step ca bootstrap --ca-url … --fingerprint …` for the **calling user**
   (`~/.step`), so `step ca …` commands work without `--ca-url/--root`. The root certificate is
   only accepted if its SHA-256 fingerprint matches.
5. **Optional trust:** copies the root certificate to `/usr/local/share/ca-certificates/` and runs
   `update-ca-certificates`.

## Options

| Option | Environment | Meaning |
|---|---|---|
| `--ca-url URL` | `STEP_CA_URL` | step-ca to bootstrap to |
| `--fingerprint FP` | `STEP_FINGERPRINT` | SHA-256 fingerprint of the root certificate |
| `--trust` / `--no-trust` | `STEP_TRUST=yes/no` | add the root to the system trust store |
| `--yes` | `ASSUME_DEFAULTS=1` | no questions |

Without a terminal the script runs as with `--yes`.

## Getting the CA URL and the fingerprint

On the step-ca host:

```bash
step certificate fingerprint $(step path)/certs/root_ca.crt
# or from any host that already has the root certificate:
step certificate fingerprint root_ca.crt
```

The URL is the `address` from the CA's `ca.json` with a DNS name or IP that is in the CA's
`dnsNames`, e.g. `https://ca.lab:9000`. Check it with `step ca health --ca-url … --root root_ca.crt`.

If the host uses an HTTP(S) proxy, put the CA into `NO_PROXY`/`no_proxy`.

## License

MIT License. Feel free to use and modify.
