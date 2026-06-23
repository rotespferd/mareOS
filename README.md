# mareOS

**A secure-by-default immutable developer workstation** — a proof of concept that
combines [BlueBuild](https://blue-build.org/) with the developer-safety practices from
[crftd.tech "Notes on safer development"](https://crftd.tech/blog/2026-05-30-notes-on-safer-development/).

mareOS is a custom [Fedora Atomic](https://fedoraproject.org/atomic-desktops/)
(`bootc`/`rpm-ostree`) image built on the Universal Blue GNOME base. It bakes
supply-chain hardening into the OS itself, so a fresh install is a hardened dev
machine by default instead of something each developer must harden by hand.

> See [CONCEPT.md](./CONCEPT.md) for the full architecture and rationale.

## What's hardened out of the box

| Tier | What | How |
|---|---|---|
| OS (highest trust) | base + this image | atomic, **cosign-signed**, instant rollback |
| Dev tooling (sandbox) | editor, browser, dev envs | **Flatpaks** + **distrobox/devcontainers** — never on the host |
| Project deps (lowest trust) | npm/pip/… packages | only inside containers; **pinned, install-scripts off, release-age cooldown** |

- **No project toolchains on the host** — `npm`/`pip`/`mvn`/`go`/`cargo` are absent by design.
- **Editor in a Flatpak sandbox** with restricted filesystem access and auto-update disabled.
- **Podman refuses unsigned images** from trusted registry scopes (sigstore policy).
- **Safe defaults pre-seeded** (`/etc/skel/.npmrc`, pip config, editor settings).
- **AI-agent policy** shipped at `/usr/share/mareos/AGENTS.md`.
- **Firewall on, kernel/network sysctl hardening.**
- **The build pipeline dogfoods the rules** — digest-pinned base, Renovate cooldowns, cosign signing.

## Repository layout

```
recipes/recipe.yml      # the BlueBuild image definition
files/system/           # hardened config copied verbatim into the image (-> /)
scripts/                # build-time hardening (flatpak overrides, signature policy)
.github/workflows/      # build + sign pipeline (SHA-pinned, cosign)
renovate.json5          # digest pinning + release-age cooldown
cosign.pub              # signing public key (private key = SIGNING_SECRET secret)
```

## Build it

1. Use this repo as a template on GitHub and enable Actions.
2. Generate signing keys and add the secret:
   ```sh
   cosign generate-key-pair
   # commit cosign.pub; add cosign.key contents as the SIGNING_SECRET repo secret
   ```
3. Push. The `build-mareos` workflow builds and signs `ghcr.io/<you>/mareos`.

Locally (rootful podman):
```sh
bluebuild build recipes/recipe.yml
```

## Try it (in a VM — do not rebase your daily driver first)

Boot a Fedora Atomic ISO in a VM, then:

```sh
# 1. rebase (unverified, first hop)
rpm-ostree rebase ostree-unverified-registry:ghcr.io/<you>/mareos:latest
systemctl reboot

# 2. move to the signature-verified ref
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/<you>/mareos:latest
systemctl reboot
```

Verify the image signature beforehand:
```sh
cosign verify --key cosign.pub ghcr.io/<you>/mareos
```

## Daily workflow

```sh
just --justfile /usr/share/mareos/justfile dev-init   # create pinned dev containers
just --justfile /usr/share/mareos/justfile node       # enter the Node env (npm lives here)
```

## Status

Proof of concept. See open validation items at the bottom of [CONCEPT.md](./CONCEPT.md)
(kernel args, digest-pin syntax, signed-rebase bootstrap, flatpak sandbox tightness).
