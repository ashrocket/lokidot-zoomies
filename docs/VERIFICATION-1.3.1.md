# Version 1.3.1 verification

Verified on the owner's Apple Silicon Mac on 31 October 2026.

The source was cloned freshly from GitHub after the prior checkout, installed app, and launcher were moved to macOS Trash. The standard app built with the whippet-head icon, and all 34 existing XCTest cases passed. The app and its bundled helpers passed strict code-signature checks. The icon contains the standard and Retina representations. Its metadata reports version 1.3.1, build 3.

The generated PKG advertised only `CurrentUserHomeDirectory`. Installing that PKG with Apple's `installer` completed successfully at the owner's home directory. The resulting app is in `~/Applications`, passes strict signature verification, and opens its playground with Whippet selected. The optional launcher reports version 1.3.1. The native UI exposes Add your dog and the existing play/pause controls.

Only Beagle, Robot Loki, and Whippet are bundled. Personal sprite packs are not copied into the repository, ZIP, or installer. The installer disables relocation so an older copy in Trash is not selected for the update. Independent source review covered the install domain, ownership, distribution schema, icon packaging, and preserving custom `--pack` builds.

The app has an ad-hoc local signature; the PKG is unsigned. Developer ID signing, notarization, Intel execution, and other macOS versions were not verified here. GitHub Actions builds are a separate check and retain the ZIP and PKG as artifacts.
