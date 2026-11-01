# macOS updates

The standard app checks GitHub for stable releases when launched, then checks hourly whether a day has passed since its last attempt. The last attempt is saved across launches, so automatic requests run at most once per 24 hours. Turn **Automatically Check for Updates** off in the Zoomies application or paw menu to stop background checks. **Check for Updates…** checks immediately, regardless of that setting.

When an update is available, the app shows the current and new versions and asks **Download and Install** or **Later**. Nothing is downloaded until you choose Download and Install. Background checks offer each version once; use Check for Updates to see an offer again. Offline errors, rate limits, and invalid releases do not interrupt background use. Manual checks explain failures.

After consent, Zoomies downloads and verifies the package, then opens macOS Installer and quits normally. Installer asks you to confirm and finishes installation. Reopen **~/Applications/LokiDot Zoomies.app** afterward. There is no silent installation or automatic restart. If the running copy lives elsewhere, the offer explains that Installer updates the copy in ~/Applications. Personal dog folders and app preferences are not changed by the updater.

Only `com.ashrocket.LokiDotZoomies` uses this updater. Separately identified `--pack` builds have no update menus or background checks. The updater chooses the architecture of its executable: arm64 or x86_64. An Intel build running through Rosetta therefore requests the Intel package.

## Release and download rules

The only metadata endpoint is `https://api.github.com/repos/ashrocket/lokidot-zoomies/releases/latest`. Requests use an ephemeral URLSession without credentials, cookies, cache, telemetry, or an account. Ordinary HTTPS validation remains enabled. Metadata redirects are rejected. Requests time out after 20 seconds without progress, with total limits of 30 seconds for metadata and five minutes for packages.

Release tags must be stable `vMAJOR.MINOR.PATCH`, with numeric components, no leading zeros, suffixes, or overflow. The app compares them numerically with `CFBundleShortVersionString`. Drafts and prereleases are rejected. The release page must match this repository and tag exactly. An equal or older release is not an upgrade.

A newer release must contain exactly one uploaded asset named `LokiDot-Zoomies-VERSION-macos-ARCH.pkg`. Its `browser_download_url` must match the exact GitHub owner, repository, tag, and filename. The declared package size must be positive and no more than 128 MiB. Metadata is capped at 1 MiB, including streamed responses. Missing or malformed digests prevent downloading; the [GitHub assets API](https://docs.github.com/en/rest/releases/assets) supplies the required `sha256:` digest followed by 64 hexadecimal characters.

Package redirects accept only HTTPS on the exact hosts `release-assets.githubusercontent.com`, `objects.githubusercontent.com`, and `github-releases.githubusercontent.com`, with no URL credentials, fragments, or nonstandard ports. At most five redirects are allowed. Unexpected hosts, statuses, response lengths, or excessive streamed bytes stop the transfer.

Each approved transfer creates a unique mode-0700 temporary directory and an exclusive mode-0600 file. Bytes are hashed incrementally while writing. The completed byte count and SHA-256 must match the metadata before Installer can open the file. The file receives macOS quarantine metadata; no quarantine flags or security settings are removed. Failed transfers remove only their own generated scratch directory. Successfully verified files remain in the private temporary folder for Installer and later system cleanup.

Immediately before opening Installer, the app reopens the staged file without following symbolic links, checks that it is a private regular file owned by the current user, and hashes its bytes again. It checks file identity, size, modification time, and quarantine before handoff. These checks prevent other users from replacing the staged download; they do not eliminate every race with a malicious process already running as the same user.

The checksum establishes consistency with GitHub’s HTTPS metadata; it is not a Developer ID signature or notarization. The current package is unsigned and the app is ad-hoc signed. Normal macOS security prompts still apply. This updater never runs shell commands, `sudo`, or the command-line installer.

## Verification

`./lokidot test` includes deterministic tests for numeric version ordering, canonical tags, release identity, architecture selection, draft/prerelease rejection, asset uniqueness/state/size/URL/digest, oversized metadata, exact redirect hosts, and streamed integrity checks (correct, truncated, oversized, and same-size altered bytes). These tests do not contact GitHub or install an update.

The same command also runs `scripts/test-update-staging.swift` against the production staged-file verifier. A valid private quarantined fixture must pass; altered or truncated bytes, missing quarantine, permissive permissions, symbolic links, hard links, and FIFOs must fail. The probe uses only its own synthetic temporary files and removes them when finished.

The normal build compiles the AppKit controller and URLSession transport and packages them in the standard app. End-to-end update acceptance requires a newer real release carrying its architecture-matched package and GitHub digest, explicit user consent, and native Installer completion. A successful source build or parser test alone does not establish that end-to-end result.
