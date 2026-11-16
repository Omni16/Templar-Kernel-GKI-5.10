# Device inputs release — `device-inputs-v1`

The workflow does not commit the 320 MB of device images to git.  They are
uploaded once to the GitHub release `device-inputs-v1` and downloaded by the
build job with `gh release download`; `configs/device-inputs.sha256` is
verified before anything is unpacked.

## Assets

| Asset | Size | SHA-256 |
| --- | ---: | --- |
| `boot.img.xz` | 15 MiB | decompresses to `boot.img` (192 MiB); SHA-256 `e4df49671a7195b7b2bf1c0a0aaa712625eb385f46d92991ca0fccb1c197d515` |
| `vendor_boot.img.xz` | 15 MiB | decompresses to `vendor_boot.img` (96 MiB); SHA-256 `3b545d9a62d2db8daf7d0dc55f3d56273949085748fea91bf069787e021dd0cd` |
| `vendor_dlkm_a.img` | 27.6 MiB | `f20fc15e2e1048fd0fcf39589239672f7adc6ee849bb07ce47fc995122ecfa7a` |
| `vbmeta.img` | 8 KiB | `1adc50c8d9fbadaf7cf4c75b19b54133aa7bf0c56a0cd0a7e59f274e2a19393e` |
| `config-5.10.236-gsi-marble` | ~250 KiB | `aa19d5a2ad009afb5a8968e8a880790a4657c659041ac15c89e4b7ce6c0a04b6` |
| `SHA256SUMS` | ~500 B | checksums for the files above |

`vendor_dlkm_b` was 0 bytes in the original dump and is intentionally not
uploaded.  The source of these files and the extraction details are in
`kernel-images/README.md` in the development environment; only the images and
the extracted base config are required by CI.

## Create the release

From a checkout containing the files (or point `--repo` at the repository and
provide absolute paths):

```bash
cd /root
cp /root/Templar-Kernel-GKI-5.10/configs/device-inputs.sha256 /root/SHA256SUMS
gh release create device-inputs-v1 \
  --repo Omni16/Templar-Kernel-GKI-5.10 \
  --title "Zyomi16 marble device inputs v1" \
  --notes-file /root/Templar-Kernel-GKI-5.10/docs/device-inputs-release.md \
  /root/boot.img.xz \
  /root/vendor_boot.img.xz \
  /root/vendor_dlkm_a.img \
  /root/vbmeta.img \
  /root/config-5.10.236-gsi-marble \
  /root/SHA256SUMS
```

The workflow only needs `contents: read`; `GH_TOKEN` is the automatic
`github.token`.  If the release is private, the same token can read it in the
repository's Actions run.  Re-running the upload with `--clobber` for an
individual asset is also fine:

```bash
gh release upload device-inputs-v1 boot.img.xz --repo Omni16/Templar-Kernel-GKI-5.10 --clobber
```

## Verification performed by CI

```bash
gh release download device-inputs-v1 --repo "$GITHUB_REPOSITORY" --dir device-inputs
cd device-inputs
for name in boot.img vendor_boot.img; do
  xz -dc "${name}.xz" > "${name}"
done
sha256sum -c ../configs/device-inputs.sha256
cmp config-5.10.236-gsi-marble ../configs/base-marble-5.10.236.config
```

The `cmp` is important: the workflow builds from the committed
`configs/base-marble-5.10.236.config`, so the release copy must stay identical
to the extracted config.

## Provenance

The images were extracted from the POCO F5 / Redmi Note 12 Turbo dump used for
this project.  `boot.img` contains a GKI 5.10.236 kernel and a generic
ramdisk.  `vendor_boot.img` contains the vendor ramdisk and the marble DTB.
`vendor_dlkm_a.img` is the slot A EROFS vendor_dlkm image.  `vbmeta.img` is
the top-level AVB metadata supplied with the dump; it is not a
`vbmeta_system` image.

The stock vendor modules in these images are from a different GKI build
(`5.10.160-gki-gd28eeb36ae86`).  See `docs/COMPATIBILITY.md` before flashing a
boot-only image onto a stock ROM.
