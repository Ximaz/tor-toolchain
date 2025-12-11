# Tor Toolchain

This repository contains a Dockerfile that, once built, compiles all the Tor
project binaries. This is specially nice to have when wanting to use Tor as a
proxy locally without actually installing Tor binaries on your host.

## Usage

The `Dockerfile` located at the root of the project is responsible for building
the binaries.

It accepts a build parameter called `TOR_VERSION` which corresponds to a Tor
version, a tag from the official repository :
`https://gitlab.torproject.org/tpo/core/tor`
`TOR_VERSION` defaults to `0.4.8.21` if unspecified, as for today, it's the
latest version released.

For easy build, there is a `docker-compose.yml` file which builds everything for
you, and you can specify the Tor version in the `args` attribute of the `build`
context. To build locally, use this command :
```bash
docker compose -f docker-compose.yml build
```

At the end, you should have a new image called `tor-toolchain`, from which you
can derive new Docker image in order to, let's say, use a custom `torrc` config.

## Tor Proxy

A `tor-proxy` Docker Compose service has been added which lets you setup a Tor
proxy locally easily. It is a `SOCK5` proxy, reachable on port `9050`, with a
Controller on port `9051`.

To start the proxy, use the following command :
```bash
docker compose -f docker-compose.yml up tor-proxy --build -d
```
The default `torrc` configuration can be modified at the root of the project to
satisfy your needs.

Once started, make sure it works fine before attempting anything else. Use the
following command to ensure the proxy is reachable and works as expected :
```bash
curl -s -x socks5h://127.0.0.1:9050 https://check.torproject.org | \
grep "Congratulations. This browser is configured to use Tor." >/dev/null && \
echo "Protected." || "Careful, you are not protected."
```

If you see `Protected.`, your proxy is setup correctly and locally reachable. If
not, you should check the logs of the container, something is not working as
expected, thus you are not protected yet.
