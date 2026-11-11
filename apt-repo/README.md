# AsterHand iOS software source

[English](README.md) · [简体中文](README.zh-CN.md)

> **The signed APT source is being migrated.** Use the matching DEB from the [main release](https://github.com/yaroslav830/AsterHand/releases/tag/v1.0-build82-monorepo). Follow the source installation steps below after the signed source is deployed.

**[Planned APT site](https://yaroslav830.github.io/AsterHand/ios-apt/)**

## Install from the software source

1. Run `dpkg --print-architecture` in an existing device terminal. This only reads the bootstrap architecture.
2. In Sileo or Zebra → Sources → Add Source, add the matching URL below. The website offers one-tap buttons; legacy Cydia supports Rootful.
3. Refresh, search **AsterHand**, select **Get / Install**, review the dependency queue and confirm. Each environment-specific source includes native OpenSSH and its runtime dependencies.
4. Open AsterHand, connect your AI service and enable the Root and screen permissions you need. To update, refresh the package manager and approve the upgrade.

| Environment | dpkg architecture | Source | Minimum AsterHand target |
| --- | --- | --- | --- |
| Rootful / Elucubratus | `iphoneos-arm` | `https://yaroslav830.github.io/AsterHand/ios-apt/rootful/` | iOS 14 |
| Rootless | `iphoneos-arm64` | `https://yaroslav830.github.io/AsterHand/ios-apt/rootless/` | iOS 15 |
| RootHide | `iphoneos-arm64e` | `https://yaroslav830.github.io/AsterHand/ios-apt/roothide/` | iOS 15 |

Architectures identify bootstrap layouts, not CPU ABI. **Procursus Rootful users:** keep your bootstrap's OpenSSH and use the [unified AsterHand-only source](https://yaroslav830.github.io/AsterHand/ios-apt/). Do not replace your bootstrap to install this app.

The unified flat source automatically selects the native AsterHand DEB in Sileo/Zebra and uses existing bootstrap sources for dependencies. Complete OpenSSH sets are isolated by environment because upstream `Architecture: all` packages can still contain environment-specific paths. Package bytes and architecture labels are preserved.

Adding a source installs nothing and grants no Root permission. Installing OpenSSH can start its upstream SSH service; configure your login credentials or SSH keys. Safari can identify iOS, but cannot identify your jailbreak. The optional [read-only detector](detect-environment.sh) reads actual dpkg architecture.

## Automatic updates

The [APT workflow reference](ios-apt-workflow.example.yml) is retained. To resume deployment, include the signed output under ios-apt/ in the website artifact and deploy both in one Pages run. The update process works as follows.

- AsterHand follows this repository's **latest stable GitHub Release**, requiring all three matching DEBs. It validates SHA-256, size, package ID, version, firmware target and architecture. Arbitrary source commits are never treated as installable releases.
- OpenSSH follows the latest **packaged stable** versions for Elucubratus, Procursus iOS 15 baseline and RootHide iOS 15 baseline. Debian version rules resolve `Depends` and `Pre-Depends`; firmware, dpkg and RootHide itself remain bootstrap-provided. A newer incompatible upstream source release is not substituted.
- Upstream bytes, maintainers, notices, source material and SHA-256 provenance are preserved. All four APT indices are signed with the existing key. A failed download/check stops deployment and leaves the live source intact. AsterHand downgrades and different bytes under an existing version are rejected: increase the DEB `Version` for an upgrade.

This updates the source, not devices silently. GitHub can delay scheduled runs or disable them after prolonged inactivity: [schedule behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

[Live package provenance](https://yaroslav830.github.io/AsterHand/ios-apt/upstream-packages.json) · [Third-party notices and source material](https://yaroslav830.github.io/AsterHand/ios-apt/third-party/README.md)

## Rebuild and signing

Requires Python **3.14+** and GnuPG. Keep the private signing home outside source control and public output. Actions uses the repository secret `APT_SIGNING_PRIVATE_KEY`, containing only the dedicated existing APT signing key. No personal GitHub token or other private keys belong there. No fork/PR trigger is enabled. Actions has Pages deployment permission, not source-write permission; set GitHub Pages publishing source to **GitHub Actions**.

```sh
python -m unittest discover -s tests -p test_ios_apt_common.py
python scripts/sync_ios_apt_upstreams.py --output build/apt-artifacts
python scripts/collect_ios_apt_notices.py build/apt-artifacts
python scripts/build_ios_apt_repo.py --artifacts build/apt-artifacts --dependencies build/apt-artifacts/dependencies.json --output build/ios-apt-site --gpg-home .private/apt-signing --key 457D056969DE0D9DB31C0259025BDCAD4FDCD88C
python scripts/check_ios_apt_repo.py build/ios-apt-site
```

Local builds can pass `--release-json` and `--roothide-commit` for an exact GitHub metadata snapshot. On Windows, supply Git for Windows `--gpg` / `--gpgv` paths. Only deploy the generated site. Signing fingerprint: **457D056969DE0D9DB31C0259025BDCAD4FDCD88C**. Manual APT configuration must trust the public key with `Signed-By`; never disable signature verification.
