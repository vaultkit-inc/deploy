#!/usr/bin/env bash
# Tests scripts/install.sh against a local copy of this repository with real
# git tags and a stub docker. Run with: test/install_test.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0
pass () { PASSED=$((PASSED + 1)); echo "ok   $1"; }
flunk () { FAILED=$((FAILED + 1)); echo "FAIL $1"; }
check () { if eval "$2"; then pass "$1"; else flunk "$1"; fi; }

# docker stub: images in $MISSING_IMAGES don't exist, and $RUNNING_IMAGE is
# what the control plane container runs.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/docker" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  manifest) [[ " ${MISSING_IMAGES:-} " != *" $3 "* ]] ;;
  inspect) [ -n "${RUNNING_IMAGE:-}" ] && echo "$RUNNING_IMAGE" ;;
  *) exit 0 ;;
esac
STUB
printf '#!/bin/sh\necho 203.0.113.9\n' > "$WORK/bin/curl"
chmod +x "$WORK/bin/docker" "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"

# A deploy repository whose main has the given releases, each tagged.
git init -q -b main "$WORK/seed"
cd "$WORK/seed"
git config user.email test@example.com
git config user.name test
tar -C "$REPO_DIR" --exclude=.git --exclude=.env --exclude=test -cf - . | tar -xf -
for version in 0.9.2-alpha 0.9.3-alpha 0.9.10-alpha 1.0.0-alpha 1.0.0; do
  sed -i.bak "s/^VAULTKIT_VERSION=.*/VAULTKIT_VERSION=$version/" .env.example
  rm -f .env.example.bak
  echo "$version" > RELEASE
  git add -A
  git commit -qm "$version"
  git tag -a "v$version" -m "v$version"
done
echo "0.9.3-alpha console crashes on start" >> BROKEN_VERSIONS
git add -A
git commit -qm "Mark 0.9.3-alpha broken"
git clone -q --bare . "$WORK/origin.git"

CASE=0
fresh_clone () {
  CASE=$((CASE + 1))
  DIR="$WORK/install-$CASE"
  git clone -q "$WORK/origin.git" "$DIR"
}
install () { (cd "$DIR" && ./scripts/install.sh "$@") >"$WORK/out" 2>&1; }
env_version () { sed -n 's/^VAULTKIT_VERSION=//p' "$DIR/.env"; }
release () { cat "$DIR/RELEASE"; }
out_has () { grep -q -- "$1" "$WORK/out"; }

# A new install takes the latest release, and its files.
fresh_clone
install
check "fresh install succeeds" '[ $? -eq 0 ]'
check "fresh install takes the latest version" '[ "$(env_version)" = 1.0.0 ]'
check "fresh install checks out the release" '[ "$(release)" = 1.0.0 ]'
check "fresh install generates secrets" '! grep -q "=change-me" "$DIR/.env"'
check "fresh install generates keys" '[ -f "$DIR/secrets/keys/vkit_priv.pem" ]'
check "the plain-HTTP hint mentions FORCE_SSL" 'out_has "FORCE_SSL=false"'

# A specific version gets that release's compose file and .env.example.
fresh_clone
install --version 0.9.2-alpha
check "--version installs that version" '[ "$(env_version)" = 0.9.2-alpha ] && [ "$(release)" = 0.9.2-alpha ]'
check "a leading v is accepted" 'fresh_clone; install --version v0.9.2-alpha; [ "$(env_version)" = 0.9.2-alpha ]'

# Rerunning keeps the version, however far main has moved.
fresh_clone
install --version 0.9.2-alpha
SECRET="$(grep ^JWT_SECRET= "$DIR/.env")"
install
check "rerunning keeps the installed version" '[ "$(env_version)" = 0.9.2-alpha ] && [ "$(release)" = 0.9.2-alpha ]'
check "rerunning keeps the secrets" '[ "$(grep ^JWT_SECRET= "$DIR/.env")" = "$SECRET" ]'
check "rerunning mentions the newer release" 'out_has "1.0.0 is available"'

# Upgrades, including versions that only sort correctly as versions.
install --version 0.9.10-alpha
check "upgrades past 0.9.9" '[ "$(env_version)" = 0.9.10-alpha ] && [ "$(release)" = 0.9.10-alpha ]'
check "an upgrade says how to apply it" 'out_has "docker compose pull"'
install --version 1.0.0-alpha
install --version 1.0.0
check "a release is newer than its prerelease" '[ "$(env_version)" = 1.0.0 ]'

# Downgrades are refused and change nothing.
install --version 1.0.0-alpha
check "refuses a downgrade to a prerelease" '[ $? -ne 0 ] && out_has "older"'
install --version 0.9.2-alpha
check "refuses a downgrade" '[ $? -ne 0 ] && out_has "backwards"'
check "a refused downgrade changes nothing" '[ "$(env_version)" = 1.0.0 ] && [ "$(release)" = 1.0.0 ]'

# Versions that can't be installed.
fresh_clone
install --version 0.9.1-alpha
check "refuses a version with no deploy tag" '[ $? -ne 0 ] && out_has "isn.t available" && out_has "0.9.2-alpha"'
install --version 0.9.3-alpha
check "refuses a broken version" '[ $? -ne 0 ] && out_has "console crashes on start"'
MISSING_IMAGES="ghcr.io/vaultkit-inc/funl-runtime:0.9.2-alpha" install --version 0.9.2-alpha
check "refuses a release with a missing image" '[ $? -ne 0 ] && out_has "funl-runtime:0.9.2-alpha"'
check "a refused install creates no .env" '[ ! -f "$DIR/.env" ]'

# A broken version is refused from an install on an older tag, because the
# list is read from main.
fresh_clone
install --version 0.9.2-alpha
install --version 0.9.3-alpha
check "an older checkout still sees the broken list" '[ $? -ne 0 ] && out_has "console crashes on start"'

# Local changes aren't overwritten.
fresh_clone
install --version 0.9.2-alpha
echo "# edited" >> "$DIR/docker-compose.yml"
install --version 1.0.0
check "refuses to overwrite local changes" '[ $? -ne 0 ] && out_has "docker-compose.yml" && out_has "CONSOLE_BIND"'
check "local changes survive" 'grep -q "# edited" "$DIR/docker-compose.yml"'

# Installs from before .env held the version.
fresh_clone
cp "$DIR/.env.example" "$DIR/.env"
sed -i.bak '/^VAULTKIT_VERSION=/d' "$DIR/.env"
rm -f "$DIR/.env.bak"
RUNNING_IMAGE="ghcr.io/vaultkit-inc/control-plane:0.9.2-alpha" install
check "an older install keeps the version it runs" '[ "$(env_version)" = 0.9.2-alpha ] && [ "$(release)" = 0.9.2-alpha ]'

fresh_clone
cp "$DIR/.env.example" "$DIR/.env"
sed -i.bak '/^VAULTKIT_VERSION=/d' "$DIR/.env"
rm -f "$DIR/.env.bak"
RUNNING_IMAGE="ghcr.io/vaultkit-inc/control-plane:0.9.0-alpha" install
check "an install on a withdrawn release moves to the latest" '[ "$(env_version)" = 1.0.0 ]'
check "...and says how to apply it" 'out_has "Moving from 0.9.0-alpha to 1.0.0"'

# Usage errors.
fresh_clone
install --version
check "--version needs a value" '[ $? -ne 0 ] && out_has "needs a version"'
install --bogus
check "rejects unknown options" '[ $? -ne 0 ] && out_has "Unknown option"'

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
