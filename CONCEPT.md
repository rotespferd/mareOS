# mareOS — Concept & Architecture

## Why

The 2026 wave of supply-chain attacks
([crftd.tech](https://crftd.tech/blog/2026-05-30-notes-on-safer-development/)) exploits a
simple truth: developers routinely execute unreviewed third-party code — install scripts,
`curl | bash`, `npx`, AI agents auto-installing dependencies. Hardening a dev machine to
resist this is real work that almost nobody is trained to do, and it has to be redone on
every machine.

[BlueBuild](https://blue-build.org/) lets us build a **signed, immutable, atomic** OS image
declaratively. So instead of asking each developer to harden their laptop, we **bake the
safer-development practices into the OS image**. Install mareOS → you start hardened.

## The core idea: trust stratification maps onto OS layers

The article's central framework is that different software sources deserve different trust,
and different update policies. An immutable OS already has these layers — we just align them:

| Trust tier | Update policy | mareOS realization |
|---|---|---|
| **OS vendor** (highest) | auto-update fine | Fedora Atomic + Universal Blue base + the mareOS image. Atomic `bootc`/`rpm-ostree` updates, cosign-signed, with one-command rollback. Read-only root. |
| **Dev tooling** (medium) | must be sandboxed | Editor & browser as **Flatpaks**; dev environments as **distrobox**/**devcontainers**. None of it installed on the host. |
| **Project dependencies** (lowest) | rigorous, pinned, cooled-down | Live only *inside* containers. Shipped configs enforce digest pinning, `ignore-scripts`, exact versions, and release-age cooldowns. |

Immutability gives tier 1 essentially for free. mareOS's real work is **enforcing tiers 2
and 3 by default**.

## How each control is implemented

All file paths are in this repo; `files/system/*` is copied verbatim to `/` in the image.

### Tier 1 — the OS
- `base-image: ghcr.io/ublue-os/base-main` in `recipes/recipe.yml` (pin by `@sha256` digest
  for production; Renovate manages it).
- `signing` module + `.github/workflows/build.yml` → the published image is cosign-signed;
  `cosign.pub` lets users verify and do **signature-verified rebases**.
- Atomicity & rollback come from `rpm-ostree`/`bootc` (`rpm-ostree rollback`).

### Tier 2 — sandboxed dev tooling, never on the host
- `dnf` module installs **only** what's needed to *run* containers (`distrobox`,
  `podman-compose`, `cosign`, `just`, `age`, `sops`). It deliberately installs **no**
  `node`/`npm`/`pip`/`mvn`/`go`/`cargo`. Running `npm` on the host is impossible → isolation
  by construction.
- `default-flatpaks` installs VSCodium, Firefox, Flatseal from Flathub.
- `scripts/flatpak-harden.sh` writes `/etc/flatpak/overrides/com.vscodium.codium` to strip
  the editor's broad home/host filesystem access (grant per-project folders explicitly).
- `files/system/usr/share/mareos/distrobox.ini` — curated dev environments pinned by
  **digest**; `justfile` wraps the safe workflow so nobody hand-rolls a `curl | bash`.

### Tier 3 — project dependencies, contained and pinned
- `/etc/skel/.npmrc` → `ignore-scripts=true`, `save-exact=true`, `before-age` cooldown.
- `/etc/skel/.config/pip/pip.conf` → prefer wheels, no surprises.
- `/etc/skel/.var/app/.../settings.json` → editor auto-update **off**, workspace trust **on**,
  telemetry off.
- `/usr/share/mareos/AGENTS.md` → the article's agent rules (no `@latest`, no `npx`/`uvx`, no
  fetch-and-execute, cooldowns, digest pins, "STOP — don't fall back to a weaker path").

### Cross-cutting hardening
- `scripts/podman-verify.sh` merges a **sigstoreSigned** requirement into
  `/etc/containers/policy.json` for trusted scopes (e.g. `ghcr.io/ublue-os`), paired with
  `files/system/etc/containers/registries.d/mareos-sigstore.yaml`. Unsigned pulls in an
  enforced scope are refused.
- `systemd` module enables `firewalld` (default-deny inbound).
- `files/system/etc/sysctl.d/99-mareos-hardening.conf` — kernel/network sysctl hardening
  (kptr/dmesg restrict, ptrace scope, unprivileged BPF off, rp_filter, protected_*; user
  namespaces left ON because podman/flatpak need them).
- `kargs` module — conservative kernel args (`init_on_alloc/free`, page shuffle); stronger
  options (`lockdown`, `slab_nomerge`) commented pending VM validation.

## The build pipeline dogfoods the rules

mareOS is itself built following the article:
- `.github/workflows/build.yml` — third-party actions to be SHA-pinned; cosign-signed output.
- `renovate.json5` — `helpers:pinGitHubActionDigests`, `pinDigests` for container images, and
  a `minimumReleaseAge` cooldown so a freshly compromised upstream isn't adopted instantly.
  No auto-merge; every bump is reviewed.
- No fetch-and-execute anywhere in the build; the ublue verification key is **vendored**, not
  curled.

## Verification (do this in a VM, never on your daily driver first)

1. **Build:** push to GitHub (Actions builds & signs) or `bluebuild build recipes/recipe.yml`.
2. **Signature:** `cosign verify --key cosign.pub ghcr.io/rotespferd/mareos`.
3. **Rebase** a Fedora Atomic VM (unverified hop → signed ref; see README).
4. **Assert controls hold:**
   - `which npm node pip mvn` → all absent on host.
   - `just …/justfile dev-init` then `distrobox enter dev-node` → works; `npm` exists there.
   - `podman pull` of an unsigned image in an enforced scope → **blocked**.
   - `firewall-cmd --state` → running; `sysctl kernel.kptr_restrict` → `2`.
   - VSCodium: Flatseal shows restricted FS; updates disabled.
   - `cat ~/.npmrc` → `ignore-scripts=true`.
5. **Rollback:** `rpm-ostree rollback` → previous deployment (tier-1 safety proven).

## Open validation items

- Aggressive kargs (`lockdown=integrity`) can break GPU/secure-boot — validate before enabling.
- Confirm BlueBuild's exact `base-image` digest-pin syntax; fall back to Renovate-managed tag
  if needed for the PoC.
- Signed rebase needs the verification policy/pubkey on the *target*; the `signing` module
  handles this for mareOS — document the user bootstrap.
- Verify the flatpak override doesn't block legitimate project access (devcontainers mitigate).
- Vendor the real Universal Blue cosign public key into
  `files/system/etc/pki/containers/ublue-os.pub` to activate base-image enforcement.
