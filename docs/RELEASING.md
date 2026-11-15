# Pushing Code and Publishing Releases

LePlay uses GitHub Actions to build and publish APKs. The workflow lives in
[`.github/workflows/release.yml`](../.github/workflows/release.yml).

## Prerequisites

- Push access to <https://github.com/Syuhadak27/leplay>
- Git, plus JDK 21 and the Android SDK for local builds (optional)
- [GitHub CLI](https://cli.github.com/) (`gh`) for status and release commands (optional)

```bash
git clone git@github.com:Syuhadak27/leplay.git
cd leplay
git remote -v
# origin  git@github.com:Syuhadak27/leplay.git
```

Use the `main` branch for releases.

---

## Normal flow: push code, get a release

1. Make and test your changes.
2. Commit and push to `main`:

```bash
git add .
git commit -m "feat: describe your change"
git push origin main
```

3. GitHub Actions runs automatically and:

   - reads the current `versionName` from `app/build.gradle.kts`;
   - bumps the patch version and increments `versionCode`;
   - builds `:app:assembleRelease`;
   - commits the version bump as `LePlay X.Y.Z [skip ci]`;
   - creates and pushes the `vX.Y.Z` tag;
   - publishes a GitHub Release containing `LePlay.apk`.

   Example: a push from `0.1.7` (`versionCode 144`) produces `0.1.8`
   (`versionCode 145`), tag `v0.1.8`, and release `LePlay 0.1.8`.

4. Monitor the build:

```bash
gh run list --repo Syuhadak27/leplay --workflow release.yml --limit 5
gh run watch RUN_ID --repo Syuhadak27/leplay
```

Or open <https://github.com/Syuhadak27/leplay/actions>.

5. Check or download the release:

```bash
gh release view --repo Syuhadak27/leplay

# Download the APK from the latest release
curl -L -o LePlay.apk \
  https://github.com/Syuhadak27/leplay/releases/latest/download/LePlay.apk
```

You do not need to edit `versionCode` or `versionName` for a normal release.
The workflow owns the version bump. Its bump commit contains `[skip ci]`, so it
does not trigger a second release.

---

## Skip the release for docs-only changes

Add `[skip ci]` to the commit message when a push should not build a release:

```bash
git add README.md docs/
git commit -m "docs: update release guide [skip ci]"
git push origin main
```

GitHub Actions will not run for that push.

---

## Manual trigger without a code change

Run the workflow from the current `main` and let it create the next patch
release:

```bash
gh workflow run release.yml --repo Syuhadak27/leplay
gh run list --repo Syuhadak27/leplay --workflow release.yml --limit 5
```

You can also use **Actions → Build & Release → Run workflow** on GitHub.

---

## Tag-based release (recovery or exact version)

A tag push builds the version currently set in `app/build.gradle.kts` and
publishes it under the tag name. Use this to recover when Actions stopped after
pushing the version bump but before creating the release, or when the current
`main` already contains the exact `versionName` you want.

```bash
git checkout main
git pull --ff-only origin main

# Confirm the version matches the tag you are about to create.
grep -nE 'versionCode|versionName' app/build.gradle.kts
# Example: versionName = "0.1.8"

git tag -a v0.1.8 -m "LePlay 0.1.8"
git push origin v0.1.8
```

Then verify:

```bash
gh run list --repo Syuhadak27/leplay --workflow release.yml --limit 5
gh release view v0.1.8 --repo Syuhadak27/leplay
```

Always create a tag from the commit whose `versionName` matches the tag, and
never reuse a tag that already has a release.

---

## Local build (optional)

```bash
./gradlew :app:assembleRelease
ls -lh app/build/outputs/apk/release/app-release.apk
```

The release build uses `app/release.keystore` when it exists. Keep the same
keystore and the same `applicationId` (`com.leplay.syd`) so Android accepts
future updates.

---

## Troubleshooting

Show the failed steps of a run:

```bash
gh run view RUN_ID --repo Syuhadak27/leplay --log-failed
```

Re-run a failed workflow:

```bash
gh run rerun RUN_ID --repo Syuhadak27/leplay
```

Delete and recreate a tag only if its release is broken and the tag has not been
used for a working APK:

```bash
git tag -d v0.1.8
git push origin :refs/tags/v0.1.8
```

Then create and push it again from the correct commit.
