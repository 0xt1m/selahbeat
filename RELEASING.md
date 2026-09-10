# Releasing SelahBeat

The pipeline is `.github/workflows/release.yml`. It fires on any `v*` tag and
does: test → archive → sign (Developer ID) → verify nested signing → notarise →
staple → DMG → sign the Sparkle appcast → publish a GitHub Release.

Everything below step 6 is one-time setup. After that, releasing is two commands.

---

## 0. What you need

- Apple Developer Program membership on team `D4DDD7PH6S`
- The `Developer ID Application: Tymofii Matviiv` certificate **with its private key**
- `gh` authenticated (already done as `0xt1m`)

---

## 1. Create the repo and push

```bash
cd /Users/tim/Documents/Projects/SelahBeat
git init
git add .
git commit -m "SelahBeat: metronome for worship drummers"
gh repo create 0xt1m/selahbeat --private --source=. --remote=origin --push
```

---

## 2. Generate the Sparkle signing keys

Sparkle signs every update with an EdDSA key. **Back the private key up
somewhere safe** — if you lose it, no installed copy can ever be updated again
and every user has to reinstall by hand.

```bash
SPARKLE_VERSION=2.9.6
curl -fsSL -o /tmp/sparkle.tar.xz \
  "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
mkdir -p /tmp/sparkle && tar -xf /tmp/sparkle.tar.xz -C /tmp/sparkle

# Creates the keypair, stores the private key in your login keychain,
# and prints the PUBLIC key.
/tmp/sparkle/bin/generate_keys

# Export the private key for CI, and back this file up offline.
/tmp/sparkle/bin/generate_keys -x ~/selahbeat-sparkle-private.pem
```

Put the printed **public** key into `Apps/macOS/Info.plist`, replacing
`REPLACE_WITH_YOUR_SPARKLE_PUBLIC_KEY`:

```bash
# Paste the public key string generate_keys printed:
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey <PUBLIC_KEY_HERE>" Apps/macOS/Info.plist
plutil -p Apps/macOS/Info.plist | grep SUPublicEDKey   # confirm it took
```

---

## 3. Enable Sparkle

It ships disabled (see README for why). Turn it on and resolve the package once:

```bash
./Scripts/enable-sparkle.sh
xcodebuild -resolvePackageDependencies -project SelahBeat.xcodeproj -scheme SelahBeat-macOS
```

Confirm the app still builds with it linked:

```bash
xcodebuild build -project SelahBeat.xcodeproj -scheme SelahBeat-macOS \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

---

## 4. Export the signing certificate

Keychain Access → **My Certificates** → expand
*Developer ID Application: Tymofii Matviiv (D4DDD7PH6S)* so you can see the
private key underneath → right-click → **Export** → `.p12`, set a password.

If the certificate does not expand to reveal a key, it was imported without
one and must be re-created in the developer portal — the export is useless
without it.

```bash
base64 -i ~/Desktop/selahbeat-cert.p12 | pbcopy   # now on your clipboard
```

---

## 5. Create an App Store Connect API key (for notarisation)

appstoreconnect.apple.com → **Users and Access** → **Integrations** →
**App Store Connect API** → generate a key with **Developer** access.

Download the `.p8` — **you only get one chance**. Note the Key ID and Issuer ID.

```bash
base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8 | pbcopy
```

---

## 6. Set the GitHub secrets

```bash
gh secret set MACOS_CERT_P12_BASE64      # paste the base64 .p12 from step 4
gh secret set MACOS_CERT_PASSWORD        # the .p12 export password
gh secret set KEYCHAIN_PASSWORD          # any random string, e.g. $(openssl rand -hex 16)
gh secret set NOTARY_KEY_P8_BASE64       # paste the base64 .p8 from step 5
gh secret set NOTARY_KEY_ID              # e.g. ABC123DEF4
gh secret set NOTARY_ISSUER_ID           # the UUID shown on the API keys page
gh secret set SPARKLE_ED_PRIVATE_KEY < ~/selahbeat-sparkle-private.pem

gh secret list                           # all seven should be listed
```

---

## 7. Dry-run the pipeline before it matters

Do **not** make your first tag `v1.0.0`. Release plumbing fails in ways you do
not want to discover on launch day — nested Sparkle signing and notarisation
are the usual culprits. Ship a throwaway version through the whole thing first.

```bash
git tag -a v0.0.1 -m "Pipeline test"
git push origin v0.0.1
gh run watch                             # follow the build
```

When it finishes:

```bash
gh release view v0.0.1                   # zip, dmg and appcast.xml attached?
gh release download v0.0.1 -p "*.dmg" -D /tmp/sbtest
open /tmp/sbtest/*.dmg                   # install it to /Applications
```

Verify Gatekeeper is satisfied — this is what notarisation buys you:

```bash
spctl -a -vvv -t install /Applications/SelahBeat.app
xcrun stapler validate /Applications/SelahBeat.app
```

Both must pass. If `spctl` says "rejected", the notarisation or stapling step
did not take and users would see "SelahBeat is damaged" on first launch.

---

## 8. Prove updates actually work

This is the step people skip and regret. Push a second throwaway tag, then
check that the **installed** v0.0.1 offers and installs it.

```bash
git tag -a v0.0.2 -m "Update test"
git push origin v0.0.2
gh run watch
```

Now launch the installed `/Applications/SelahBeat.app` and use
**SelahBeat → Check for Updates…**. It should offer 0.0.2, download, verify the
signature and relaunch. If it silently finds nothing, the usual causes are a
mismatched `SUPublicEDKey` or the appcast asset not being reachable at
`releases/latest/download/appcast.xml`.

---

## 9. Ship 1.0.0

```bash
git tag -a v1.0.0 -m "SelahBeat 1.0.0"
git push origin v1.0.0
gh run watch
```

Optionally tidy up the test releases afterwards:

```bash
gh release delete v0.0.1 --yes --cleanup-tag
gh release delete v0.0.2 --yes --cleanup-tag
```

---

## Version numbering

You do not edit versions by hand. The workflow derives them:

- `MARKETING_VERSION` — from the tag (`v1.2.3` → `1.2.3`)
- `CFBundleVersion` — `git rev-list --count HEAD`

Sparkle compares `CFBundleVersion` and requires it to increase strictly and
forever. Commit count does that automatically and survives a re-run of a
workflow, which a run number would not.

---

## Local dry run (no tag, no CI)

To reproduce the whole thing on your machine before trusting CI:

```bash
VER=0.0.1
BUILD=$(git rev-list --count HEAD)

xcodebuild archive -project SelahBeat.xcodeproj -scheme SelahBeat-macOS \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath build/SelahBeat.xcarchive \
  MARKETING_VERSION=$VER CURRENT_PROJECT_VERSION=$BUILD

xcodebuild -exportArchive -archivePath build/SelahBeat.xcarchive \
  -exportOptionsPlist Scripts/ExportOptions-DeveloperID.plist \
  -exportPath build/export

codesign --verify --deep --strict --verbose=2 build/export/SelahBeat.app

ditto -c -k --keepParent build/export/SelahBeat.app build/notarize.zip
xcrun notarytool submit build/notarize.zip \
  --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 \
  --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait

xcrun stapler staple build/export/SelahBeat.app
spctl -a -vvv -t install build/export/SelahBeat.app
```

If notarisation is rejected, get the reason:

```bash
xcrun notarytool log <submission-id> --key ... --key-id ... --issuer ...
```
