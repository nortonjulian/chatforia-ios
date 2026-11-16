# Offline third-party source notices

Profile → Legal & Support now offers Technology Across Chatforia (the shared website overview of web, backend, iOS and Android) and This App’s Licenses (the bundled offline source-notice sheet). The website remains a fallback if the bundled resource fails to load.

The generator collects LICENSE, NOTICE, COPYING, and COPYRIGHT files from all 15 pinned SwiftPM source repositories. The resource deliberately says source notices: binary SDK terms and embedded third-party notices are not established by a wrapper repository's license. Ancillary source notices are retained conservatively, including test/example files; this is not a list of binary contents.

## Reproduce

`python3 scripts/generate-third-party-notices.py` fetches exact pinned source revisions and regenerates the text and provenance manifest. `--cache /path/to/cache` can reuse source clones.

`python3 scripts/generate-third-party-notices.py --check` verifies the committed lockfile and resource hashes without network access. Run it after dependency changes and before archiving. `python3 scripts/test-third-party-notices.py` verifies dependency/resource drift detection.

## Outstanding before release

- Build in Xcode and confirm ThirdPartyNotices.txt is in the app bundle (the app uses a filesystem-synchronized project group).
- Open the screen offline on simulator/device, scroll to the end, select text, and close it. Verify larger accessibility text sizes.
- Review binary artifacts referenced by Google Ads, UMP, Unity mediation, Twilio Video and Voice. Wrapper Apache licenses must not be treated as licenses for proprietary binaries. Twilio Voice has no root license in the pinned repository. Twilio Video's root notice links to Twilio terms. Extract relevant third-party notices from the actual distributed frameworks.
- Review separately supplied assets and any non-SwiftPM dependencies before claiming complete attribution coverage.

Validation here: generator completed for 15 pinned repositories; lock/resource check and drift-detection test passed; git diff --check passed. Xcode is unavailable in the Linux environment, so no iOS compilation, packaged-resource verification, or simulator/device test is claimed. Keep this PR draft pending those checks.
