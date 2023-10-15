# Arch Linux ISO release utilities

## Prerequisites

### Install required packages
```sh
pacman -Syu --needed just archiso rsync mktorrent
```

### Configure your signing keys
Create an ``.env`` file containing your GPG key. Example:
```sh
GPGKEY='3E80CA1A8B89F69CBA57D98A76A5EF9054449A5C'
GPGSENDER='Pierre Schmitz <pierre@archlinux.org>'
```
In addition to this you need a key pair which is accepted by [PIXE](https://archlinux.org/packages/extra/x86_64/ipxe/). The files need to be named ``codesign.crt`` and ``codesign.key``.

## Creating a new ISO image

* Run ``just all`` to create all artifacts. This will create the ISO image and tar files.
* Optionally run ``just run-iso`` to test the ISO with Qemu.
* Upload the release to ***repos.archlinux.org*** with ``just upload-release``. This will just upload the artifacts into a temporary directory but not publish them.
* Log into [archlinux.org/login](https://archlinux.org/login) and create a new release entry using the [Archweb Admin](https://archlinux.org/admin/releng/release/). Use the information shown by the build process or manually re-run ``just show-info``. It is good practice to keep the field ***Available*** unchecked until the ISO image has been published and most mirrors had time to sync it. You may use ``just copy-torrent`` to copy the base64 encoded torrent file into your clipboard.
* As we only like to keep the last three ISO releases remove the oldest one from [Archweb Admin](https://archlinux.org/admin/releng/release/). Then remove the actual files from the mirror by running ``just remove-release <version>``.
* To actually publish a release and have it sync to mirror run ``just publish``.
