# Tor Toolchain

This repository contains a Dockerfile that, once built, compiles all the Tor
project binaries. This is specially nice to have when wanting to use Tor as a
proxy locally without actually installing Tor binaries on your host.

The Tor source is downloaded from the official `https://dist.torproject.org/`
release server and its GPG signature is verified against the pinned Tor signing
keys during the build, so a tampered or corrupted tarball aborts the build.

## Usage

The `Dockerfile` located at the root of the project is responsible for building
the binaries.

It accepts a build parameter called `TOR_VERSION` which corresponds to a Tor
release version, as published on the official server:
`https://dist.torproject.org/`

`TOR_VERSION` is the **single source of truth** for the project and lives as the
default of the `ARG TOR_VERSION` declaration at the top of the `Dockerfile`
(currently `0.4.9.11`, the latest release as of today). To build a different
version, override it at build time:
```bash
docker build --build-arg TOR_VERSION=0.4.9.11 -t tor-toolchain .
```

For an easy build, there is a `docker-compose.yml` file which builds everything
for you. To build locally, use this command:
```bash
docker compose -f docker-compose.yml build
```

At the end, you should have a new image called `tor-toolchain`, from which you
can derive new Docker images in order to, let's say, use a custom `torrc` config.

## Pulling the published image

CI builds a multi-arch image (linux/amd64 + linux/arm64) and publishes it to the
GitHub Container Registry, tagged with `latest`, the Tor version, and the commit
SHA:
```bash
docker pull ghcr.io/ximaz/tor-toolchain/tor-toolchain:0.4.9.11
```

The published image is **keyless-signed with cosign** and ships an SBOM and build
provenance attestation. You can verify the signature with:
```bash
cosign verify ghcr.io/ximaz/tor-toolchain/tor-toolchain:0.4.9.11 \
  --certificate-identity-regexp 'https://github.com/ximaz/tor-toolchain/.github/workflows/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Tor Proxy

A `tor-proxy` Docker Compose service has been added which lets you set up a Tor
proxy locally easily. It is a `SOCKS5` proxy, reachable on port `9050`.

The service runs hardened by default: a non-root user, a read-only root
filesystem with a `tmpfs` data directory, dropped Linux capabilities,
`no-new-privileges`, a memory limit, a healthcheck on the SOCKS port, and
`SafeSocks` enabled so DNS-leaking requests are refused (see
[Avoiding DNS leaks](#avoiding-dns-leaks-use-socks5h) below).

To start the proxy, use the following command:
```bash
docker compose -f docker-compose.yml up tor-proxy --build -d
```
The default `torrc` configuration can be modified at the root of the project to
satisfy your needs.

Once started, make sure it works fine before attempting anything else. First,
`docker compose ps` should report the container as `healthy`. Then use the
following command to ensure the proxy is reachable and works as expected:
```bash
curl -s -x socks5h://127.0.0.1:9050 https://check.torproject.org | \
grep "Congratulations. This browser is configured to use Tor." >/dev/null && \
echo "Protected." || echo "Careful, you are not protected."
```

If you see `Protected.`, your proxy is set up correctly and locally reachable. If
not, you should check the logs of the container, something is not working as
expected, thus you are not protected yet.

### Avoiding DNS leaks (use `socks5h`)

The `torrc` shipped here sets `SafeSocks 1`. Tor then **refuses** SOCKS requests
that arrive as a bare IP address, which happens when your application resolves the
hostname itself (a plain `socks5://` proxy) and leaks the lookup to your local DNS
resolver. Instead, always let Tor resolve the hostname for you by using a
**`socks5h://`** proxy URL (the `h` means "resolve the hostname remotely"; the
older `SOCKS4a` protocol behaves the same way). The verification command above
already does this.

Concretely, if a tool warns something like *"Your application (using socks5 to port
443) is giving Tor only an IP address ... may leak information"*, switch its proxy
scheme from `socks5://` to `socks5h://`. For example, with
[sherlock](https://github.com/sherlock-project/sherlock):
```bash
sherlock --proxy socks5h://127.0.0.1:9050 <username>
```
The warning disappears because the hostname is now sent to Tor for remote
resolution. To debug which connections are safe or unsafe, you can temporarily add
`TestSocks 1` to your `torrc` (it logs a line per connection, including
destinations, so leave it off in normal use).

### Securing & exposing your proxy

By default the proxy is bound to **loopback only** (`127.0.0.1:9050:9050` in
`docker-compose.yml`), so nothing outside the host can reach it. This project ships
only the Tor toolchain; **access control is your responsibility** as the operator.

If you want to share the proxy on a LAN, a Raspberry Pi, or a server (by changing
the port mapping to e.g. `0.0.0.0:9050:9050` and opening your firewall), add access
control **before** exposing it. Note that Tor's `SocksPort` cannot do
username/password authentication by itself (SOCKS credentials only drive stream
isolation), so the standard options are:

1. **IP allowlist (no extra dependencies)** — restrict who may connect from within
   your own `torrc`:
   ```
   SocksPolicy accept 192.168.1.0/24
   SocksPolicy accept 10.8.0.0/24
   SocksPolicy reject *
   ```
2. **Network layer** — firewall rules, or only expose the port over a VPN (e.g.
   WireGuard) so that only trusted peers can reach it.
3. **Credentialed access** — front this container with your own authenticating
   proxy (such as Dante, 3proxy, or gost) that speaks SOCKS5 with a username and
   password and forwards to Tor. This is deliberately left to you and is not
   bundled in the image.

Other `torrc` knobs you may want on a shared instance (tune to taste): bandwidth
and DoS ceilings (`BandwidthRate`/`BandwidthBurst`, `PerConnBWRate`),
per-destination circuit isolation (`SocksPort 0.0.0.0:9050 IsolateDestAddr
IsolateDestPort`), and `ClientOnly 1`. Do **not** enable `Sandbox 1`: its seccomp
sandbox requires glibc and does not work on this Alpine/musl image.

## Keeping Tor up to date

A scheduled workflow (`.github/workflows/check-tor-release.yml`) watches
`dist.torproject.org` weekly and opens a pull request bumping `TOR_VERSION` when
a newer stable release appears. The bump PR is built and signature-verified by CI
before it can be merged.

## License

This repository's packaging work (the `Dockerfile`, `docker-compose.yml`,
`torrc`, and CI workflows) is released under the [MIT License](LICENSE). This
project only packages upstream Tor **unmodified** and does not relicense it.

The material produced and shipped by the build keeps its own upstream licenses,
collected in [`NOTICE`](NOTICE): the compiled Tor binaries under the 3-clause BSD
license, and the bundled `geoip`/`geoip6` data (from the IPFire Location Database)
under CC BY-SA 4.0. The built image also carries Tor's own version-exact license at
`/usr/local/share/licenses/tor/LICENSE`.

"Tor" is a trademark of The Tor Project, Inc. This project is not sponsored,
endorsed by, or affiliated with The Tor Project; see the trademark notice in
[`NOTICE`](NOTICE) and <https://www.torproject.org/>.
