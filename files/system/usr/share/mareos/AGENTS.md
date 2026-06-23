# mareOS — AI coding agent security policy

This file is installed at `/usr/share/mareos/AGENTS.md`. Symlink or copy it into
your projects (`ln -s /usr/share/mareos/AGENTS.md ./AGENTS.md`) so coding agents
inherit these non-negotiable rules.

Source of the threat model:
https://crftd.tech/blog/2026-05-30-notes-on-safer-development/ — agentic AI
raises supply-chain risk because agents install and run dependencies with no
prior security assessment.

## Hard rules (never weaken, never "fall back to a faster path")

1. **Never run project tooling on the host.** `npm`, `pnpm`, `pip`, `uv`, `mvn`,
   `cargo`, `go`, `cypress`, etc. run **only inside a container** (distrobox or a
   devcontainer). The mareOS host ships none of these on purpose.

2. **No fetch-and-execute.** Never `curl … | sh`, `wget … | bash`, `npx`,
   `bunx`, `uvx`, `pipx run`, or any "download then run" one-liner. Add the
   dependency explicitly, then run the installed binary.

3. **Pin everything.**
   - No `@latest`, `@next`, or floating ranges (`^`, `~`, `*`). Use exact
     versions, and digests where the ecosystem supports them.
   - Containers/base images: reference by `@sha256:…` digest, never by tag.

4. **Disable install scripts.** Lifecycle scripts stay off
   (`ignore-scripts=true`). Don't enable them to "make an install work."

5. **Respect the cooldown.** Do not adopt a dependency version published less
   than **14 days** ago (7 days minimum for immutable registries). If a needed
   version is too fresh, stop and ask the human.

6. **Verify signatures.** Pull only images that pass signature verification
   (`cosign verify` / policy.json). If verification fails: **STOP** — do not
   pull an unsigned variant.

7. **On any blocked control: STOP and report.** Never retry with a weaker,
   faster, or less safe alternative to get past a security control.
