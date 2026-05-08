# GitHub Presentation Strategy

This document describes repository metadata and branding choices that live partly outside the Git tree.

## Repository description

Recommended description:

> Minimal, auditable Ubuntu bootstrapper for Codex CLI environments.

Alternative longer description:

> Secure Ubuntu-first installer, validator, and release scaffold for Codex CLI runtime setup.

## Topics

Recommended GitHub topics:

- `codex`
- `codex-cli`
- `ubuntu`
- `installer`
- `bootstrap`
- `bash`
- `devex`
- `automation`
- `shellcheck`
- `security-tools`
- `release-engineering`
- `open-source`

## Social preview

Recommended preview direction:

- Dark background.
- Monospace wordmark: `zcodex`.
- Short subtitle: `Auditable Codex CLI bootstrap for Ubuntu`.
- Minimal line-art flow: `validate → install → configure → verify`.
- Avoid screenshots, mascots, product logos, or busy gradients.

Suggested dimensions: 1280×640 PNG. A source SVG is available at `assets/social-preview.svg`; export it to PNG before uploading it in GitHub repository settings.

## Pinned release notes

Every GitHub Release should lead with:

1. What changed.
2. Who should upgrade.
3. Verification commands.
4. Checksums and artifacts.
5. Known limitations.

Use `docs/release-notes-template.md` as a drafting template. The automated release workflow extracts release notes from `CHANGELOG.md`, so keep changelog entries concise and user-facing.

## README posture

The README should answer these questions quickly:

- What is this?
- Is it safe to run?
- What does it support?
- How do I install or dry-run it?
- How do I troubleshoot it?
- How are releases verified?
- How can I contribute responsibly?
