#!/bin/sh
# Builds the Talos Linux OpenStack image with Sidero Labs' own imager.
#
# Runs as root on a Linux runner (build-freebsd-image reusable workflow,
# build_runner ubuntu-latest):  sh build/build.sh <version> <out-dir>
# Produces <out-dir>/image.raw.
#
# Talos is not modified: the image is what Image Factory would serve for the
# "openstack" platform with the official qemu-guest-agent extension, built
# locally because the public Factory publishes no checksum nor signature for
# its disk images. Every container used is verified first:
#   - imager and extensions catalog: keyless cosign signatures of Sidero's
#     release identity (Google accounts issuer), pinned by the verified digest;
#   - qemu-guest-agent: digest from the signed extensions catalog of the same
#     Talos release, and its own cosign signature.
set -eu

VERSION="${1:?usage: build.sh <version> <out-dir>}"
OUT="${2:?usage: build.sh <version> <out-dir>}"
COSIGN_VERSION=v3.1.4
COSIGN_SHA256=424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa
SIDERO_IDENTITY='(@siderolabs\.com$|^releasemgr-svc@talos-production\.iam\.gserviceaccount\.com$)'
SIDERO_ISSUER='https://accounts.google.com'

work=$(mktemp -d /tmp/oic-talos.XXXXXX)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$OUT"

# --- cosign, pinned ------------------------------------------------------------
curl -fsSL -o "$work/cosign" "https://github.com/sigstore/cosign/releases/download/$COSIGN_VERSION/cosign-linux-amd64"
echo "$COSIGN_SHA256  $work/cosign" | sha256sum -c - >/dev/null
chmod +x "$work/cosign"

# verified <image ref>: prints <repo>@<digest> of a Sidero-signed image
verified() {
  d=$("$work/cosign" verify "$1" --certificate-identity-regexp "$SIDERO_IDENTITY" \
        --certificate-oidc-issuer "$SIDERO_ISSUER" --output json 2>/dev/null \
      | jq -r '.[0].critical.image."docker-manifest-digest"')
  case "$d" in sha256:*) echo "${1%%:*}@$d" ;; *) echo "::error::$1 is not signed by Sidero Labs" >&2; return 1 ;; esac
}

imager=$(verified "ghcr.io/siderolabs/imager:v$VERSION")
extensions=$(verified "ghcr.io/siderolabs/extensions:v$VERSION")
echo "[build] imager $imager"
echo "[build] extensions catalog $extensions"

# qemu-guest-agent digest from the signed catalog of this Talos release
cid=$(docker create "$extensions" true)
docker cp "$cid:/image-digests" "$work/image-digests"
docker rm "$cid" >/dev/null
qga=$(grep -E '^ghcr\.io/siderolabs/qemu-guest-agent:[^@]+@sha256:[0-9a-f]{64}$' "$work/image-digests" | head -1)
[ -n "$qga" ] || { echo "::error::no qemu-guest-agent in the v$VERSION extensions catalog" >&2; exit 1; }
"$work/cosign" verify "$qga" --certificate-identity-regexp "$SIDERO_IDENTITY" \
  --certificate-oidc-issuer "$SIDERO_ISSUER" >/dev/null 2>&1 \
  || { echo "::error::$qga is not signed by Sidero Labs" >&2; exit 1; }
echo "[build] extension $qga"

# --- image ---------------------------------------------------------------------
mkdir -p "$work/out"
docker run --rm --privileged -v /dev:/dev -v "$work/out:/out" "$imager" \
  openstack --arch amd64 --system-extension-image "$qga"
ls -l "$work/out"
f=$(ls "$work/out"/openstack-amd64.* | head -1)
case "$f" in
  *.raw.xz)  xz -dc "$f" > "$OUT/image.raw" ;;
  *.raw.zst) zstd -dc "$f" > "$OUT/image.raw" ;;
  *.raw)     mv "$f" "$OUT/image.raw" ;;
  *.qcow2)   qemu-img convert -f qcow2 -O raw "$f" "$OUT/image.raw" ;;
  *) echo "::error::unexpected imager output $f" >&2; exit 1 ;;
esac
# provenance for the README / release notes
printf 'imager %s\nextension %s\n' "$imager" "$qga" > "$OUT/talos-sources.txt"
echo "[build] done: $OUT/image.raw"
