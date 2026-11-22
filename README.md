<p align="center">
  <a href="https://openimages.cloud/images/talos-linux/">
    <img src="https://openimages.cloud/img/og/talos-linux.png" alt="Talos Linux cloud image for OpenStack and Proxmox" width="720">
  </a>
</p>

<p align="center">
  <a href="https://openimages.cloud/images/talos-linux/"><img alt="Latest version" src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fimages.openimages.cloud%2Ftalos-linux%2Flatest%2FMANIFEST.json&query=%24.version&label=latest&color=2459c4&cacheSeconds=3600"></a>
  <a href="https://github.com/open-img-cloud/talos-linux/actions/workflows/release.yml"><img alt="Release" src="https://github.com/open-img-cloud/talos-linux/actions/workflows/release.yml/badge.svg"></a>
  <a href="https://openimages.cloud/verify/"><img alt="Signed with Sigstore cosign" src="https://img.shields.io/badge/signed-Sigstore%20cosign-2459c4"></a>
  <a href="https://openimages.cloud/quality/"><img alt="Boot-tested on OpenStack" src="https://img.shields.io/badge/boot--tested-OpenStack-2459c4"></a>
  <a href="LICENSE"><img alt="License GPL-2.0" src="https://img.shields.io/badge/license-GPL--2.0-555"></a>
</p>

<p align="center">
  <a href="https://openimages.cloud/images/talos-linux/"><b>Catalog page</b></a> ·
  <a href="https://images.openimages.cloud/talos-linux/latest/">Download</a> ·
  <a href="https://openimages.cloud/verify/">Verify</a> ·
  <a href="https://github.com/open-img-cloud/docs">Documentation</a> ·
  <a href="https://github.com/open-img-cloud/talos-linux/issues">Report an issue</a>
</p>

Talos Linux (qcow2) for **OpenStack** and **Proxmox VE**: the minimal, immutable OS built for
Kubernetes, managed only through its API (no SSH, no shell). Built with Sidero Labs' own
signed imager for the `openstack` platform, with the official `qemu-guest-agent` extension,
then signed with Sigstore cosign and boot-tested on a real OpenStack (a single-node Kubernetes
control plane) like every [openimages.cloud](https://openimages.cloud) image.

> **Community image.** Not an official Sidero Labs product; this project is not affiliated
> with Sidero Labs. Official images and documentation: [talos.dev](https://www.talos.dev/),
> [Image Factory](https://factory.talos.dev/).

## At a glance

| | |
|---|---|
| **Upstream** | [Talos Linux](https://github.com/siderolabs/talos) stable release, built with `ghcr.io/siderolabs/imager` (cosign-verified, pinned by digest) |
| **Extension** | `siderolabs/qemu-guest-agent`, from the signed extensions catalog of the same release |
| **Access** | Talos API (TCP 50000) with `talosctl`; Kubernetes API (6443). No SSH |
| **Configuration** | A Talos machine config (`talosctl gen config`) as user data; without it the node waits in maintenance mode |
| **Firmware** | BIOS (boot-tested) and UEFI |
| **Format** | qcow2, x86_64 (x86-64-v2 CPUs), about 4.2 GiB virtual size; the EPHEMERAL volume grows to the disk |
| **Version** | Talos release, e.g. `1.14.6` ([all versions](https://images.openimages.cloud/talos-linux/versions.json)); use `talosctl` of the same minor |

It is the image Image Factory serves for the `openstack` platform with the
`siderolabs/qemu-guest-agent` extension. We build it ourselves only because the public
Factory publishes no checksum nor signature for its disk images.

## Quick start

```sh
M=https://images.openimages.cloud/talos-linux/latest/MANIFEST.json
V=$(curl -fsS $M | jq -r .version); F=$(curl -fsS $M | jq -r .filename)
curl -fLO https://images.openimages.cloud/talos-linux/$V/$F
```

<details>
<summary><b>OpenStack: a single-node cluster</b></summary>

```sh
openstack image create --disk-format qcow2 --container-format bare \
  --property hw_qemu_guest_agent=yes --min-disk 10 --min-ram 2048 \
  --file "$F" "Talos $V"

# Security group: TCP 50000 (Talos API) and 6443 (Kubernetes API) from your address
talosctl gen config my-cluster https://<address>:6443
openstack server create --image "Talos $V" --flavor <2 vCPU, 4 GB, disk >= 10 GB> \
  --network <net> --security-group talos --user-data controlplane.yaml talos-cp1

export TALOSCONFIG=$PWD/talosconfig
talosctl config endpoint <address>; talosctl config node <address>
talosctl bootstrap
talosctl kubeconfig .
```

`hw_qemu_guest_agent=yes` is required: without the guest agent channel the extension waits
and the node stays in stage `booting`. Guide:
[Talos on OpenStack](https://docs.siderolabs.com/talos/v1.14/platform-specific-installations/cloud-platforms/openstack).

</details>

<details>
<summary><b>Proxmox VE</b></summary>

Import the disk (commands on the [catalog page](https://openimages.cloud/images/talos-linux/)),
use a CPU type of at least `x86-64-v2` (or `host`), enable the QEMU guest agent, and pass the
machine config through a cloud-init drive in the **configdrive2** format:

```sh
qm set <vmid> --cpu x86-64-v2-AES --agent 1 --ide2 local-lvm:cloudinit --citype configdrive2 \
  --cicustom user=local:snippets/controlplane.yaml
```

Without a config the node starts in maintenance mode: apply one with
`talosctl apply-config --insecure -n <address> -f controlplane.yaml`.

</details>

<details>
<summary><b>Verify the signature</b></summary>

```sh
curl -fLO https://images.openimages.cloud/talos-linux/$V/$F.bundle
cosign verify-blob "$F" --bundle "$F.bundle" \
  --certificate-identity-regexp '^https://github.com/open-img-cloud/\.github/\.github/workflows/build-(libguestfs|dib|nix-flake|freebsd)-image\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

</details>

## What this image contains

[`build/build.sh`](build/build.sh) runs Sidero Labs' imager; Talos is not modified:

- `ghcr.io/siderolabs/imager:v<version>` and the `ghcr.io/siderolabs/extensions` catalog of the
  same release, verified with cosign against Sidero's release identity and pinned by digest;
- `ghcr.io/siderolabs/qemu-guest-agent` at the digest listed by that signed catalog, its own
  signature verified too;
- the `openstack` profile of the imager (config drive first, then the metadata service).

Every release must pass the runtime contract for Talos on OpenStack, through the Talos API
with a generated machine config: config applied (client certificate accepted), etcd
bootstrapped and machine stage `running`, hostname from the metadata, IPv4 address, DNS
resolvers, EPHEMERAL volume grown to the disk, guest agent extension running, IPv6 address.

## How releases happen

1. Every day at 07:47 UTC a watcher reads the newest stable Talos release (patches of older
   minors are ignored) and opens a pull request that bumps [`VERSION`](VERSION).
2. Merging it is all it takes: the release is tagged, then the image is built, signed,
   boot-tested and published, and `latest/` and the
   [catalog](https://openimages.cloud/images/) move to it.

Talos supports the latest minor (security fixes for the two latest): older versions stay at
their immutable paths, upgrade nodes with `talosctl upgrade` one minor at a time.

## License

The tooling in this repository is under [GPL-2.0](LICENSE). Talos Linux is under the Mozilla
Public License 2.0; the image keeps the licensing terms of Talos, the Linux kernel and the
extension it contains (sources at the release tag:
[siderolabs/talos](https://github.com/siderolabs/talos),
[siderolabs/extensions](https://github.com/siderolabs/extensions)). Talos is a trademark of
Sidero Labs; this project is not affiliated with it.
