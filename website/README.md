# AsterHand official website

[English](README.md) · [简体中文](README.zh-CN.md)

Website URL: **https://yaroslav830.github.io/AsterHand/**

English is the default. The language control switches the full page and both published videos to Chinese; `?lang=zh` is a shareable Chinese link. Screenshots use the existing sanitized publication images, with generic platform labels only.

The site presents cross-device Root control, local device agents, MCP, platform releases, the iOS software source and a first-use guide. macOS and Linux have preview downloads and public source repositories. Android and Windows retain their preview/testing labels.

Build from the collection root with Python 3:

```sh
python scripts/build_asterhand_website.py --output build/website
python -m http.server 8785 --bind 127.0.0.1 --directory build/website
```

The build copies the website source, two already-published images from `docs/images`, and the four existing sanitized EN/ZH short videos in `website/media`. These videos are served by the website itself so playback does not depend on GitHub attachment access. No installers, device information, pairing records, login data or private keys belong in this source or output.

`.github/workflows/website.yml` builds and deploys this directory with GitHub Pages. Pages uses GitHub Actions; the website build uses only this collection repository. The separate iOS APT site and signing workflow are maintained in the iOS repository; the new account's signed source must be deployed and verified separately before it is advertised as available.
