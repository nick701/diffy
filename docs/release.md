# Release Notes

Diffy releases are unsigned and unnotarized until the project has an Apple Developer ID.

Current builds require macOS 26 because Diffy uses Liquid Glass APIs.

## Local Release

Run from the Mac terminal:

```bash
./script/package_release.sh <version> <build>
```

The script builds `dist/release/Diffy.app`, ad-hoc signs it, and creates `dist/release/Diffy-<version>.zip`.

## Sparkle Metadata

Sparkle update checks are enabled only when the app bundle contains both `SUFeedURL` and `SUPublicEDKey`.

```bash
export DIFFY_SPARKLE_FEED_URL="https://your-github-pages-site/appcast.xml"
export DIFFY_SPARKLE_PUBLIC_KEY="your-sparkle-eddsa-public-key"
./script/package_release.sh <version> <build>
```

After packaging, use Sparkle's `generate_appcast` tool on `dist/release` and publish the zip plus appcast over HTTPS, for example with GitHub Pages and GitHub Releases.

Current public updates are delivered through the Homebrew Cask tap. Sparkle remains packaged and metadata-gated until an appcast is deliberately published.
