export CURDIR := justfile_directory()
export VERSION := `date +%Y.%m.%d`
export GPGKEY := '3E80CA1A8B89F69CBA57D98A76A5EF9054449A5C'
export GPGSENDER:= 'Pierre Schmitz <pierre@archlinux.org>'

_default:
	@just --list

# build all artifacts
all: build create-signatures verify-signatures create-torrent latest-symlink show-info

# remove all build artifacts
clean:
	git clean -xdf -e .idea -e codesign.crt -e codesign.key

# build ISO image
build:
	#!/usr/bin/env bash
	set -euo pipefail

	TMPDIR=$(mktemp -d)

	# create an ephemeral PGP key for signing the rootfs image
	gnupg_homedir="${TMPDIR}/.gnupg"
	mkdir -p "${gnupg_homedir}"
	chmod 700 "${gnupg_homedir}"

	cat << __EOF__ > "${gnupg_homedir}"/gpg.conf
		quiet
		batch
		no-tty
		no-permission-warning
		export-options no-export-attributes,export-clean
		list-options no-show-keyring
		armor
		no-emit-version
	__EOF__

	gpg --homedir "${gnupg_homedir}" --gen-key <<EOF
		%echo Generating ephemeral Arch Linux release engineering key pair...
		Key-Type: default
		Key-Length: 3072
		Key-Usage: sign
		Name-Real: Arch Linux Release Engineering
		Name-Comment: Ephemeral Signing Key
		Name-Email: arch-releng@lists.archlinux.org
		Expire-Date: 0
		%no-protection
		%commit
		%echo Done
	EOF

	pgp_key_id="$(
		gpg --homedir "${gnupg_homedir}" \
			--list-secret-keys \
			--with-colons \
			| awk -F':' '{if($1 ~ /sec/){ print $5 }}'
	)"

	pgp_sender="Arch Linux Release Engineering (Ephemeral Signing Key) <arch-releng@lists.archlinux.org>"

	sudo GNUPGHOME="${gnupg_homedir}" mkarchiso \
		-c "${CURDIR}/codesign.crt ${CURDIR}/codesign.key" \
		-g "${pgp_key_id}" \
		-G "${pgp_sender}" \
		-m 'iso netboot bootstrap' \
		-w "${TMPDIR}" \
		-o "${CURDIR}" \
		/usr/share/archiso/configs/releng/ \

	sudo rm -rf "${TMPDIR}"
	sudo rm -f arch/boot/memtest && sudo rm -rf arch/boot/licenses/memtest86+
	# Set owner of generated files
	sudo chown -R $(id -u):$(id -g) arch archlinux-*

# create GPG signatures and checksums
create-signatures:
	for f in "archlinux-${VERSION}-x86_64.iso" "archlinux-bootstrap-${VERSION}-x86_64.tar.gz"; do \
		gpg --use-agent --sender "${GPGSENDER}" --local-user "${GPGKEY}" --detach-sign "$f"; \
	done
	for sum in sha256sum b2sum; do \
		$sum  "archlinux-${VERSION}-x86_64.iso" "archlinux-bootstrap-${VERSION}-x86_64.tar.gz" > ${sum}s.txt; \
	done

# verify GPG signatures and checksums
verify-signatures:
	for f in "archlinux-${VERSION}-x86_64.iso" "archlinux-bootstrap-${VERSION}-x86_64.tar.gz"; do \
		pacman-key -v "$f.sig"; \
	done
	for sum in sha256sum b2sum; do \
		$sum -c ${sum}s.txt; \
	done

# create a latest symlink
latest-symlink:
	ln -sf "archlinux-${VERSION}-x86_64.iso" "archlinux-x86_64.iso"
	ln -sf "archlinux-${VERSION}-x86_64.iso.sig" "archlinux-x86_64.iso.sig"
	ln -sf "archlinux-bootstrap-${VERSION}-x86_64.tar.gz" "archlinux-bootstrap-x86_64.tar.gz"
	ln -sf "archlinux-bootstrap-${VERSION}-x86_64.tar.gz.sig" "archlinux-bootstrap-x86_64.tar.gz.sig"

	# add checksums for symlinks
	for sum in sha256sum b2sum; do \
		sed "p;s/-${VERSION}//" -i ${sum}s.txt; \
	done

# create Torrent file
create-torrent:
	#!/usr/bin/env bash
	set -euo pipefail

	echo 'Creating webseeds...'
	httpmirrorlist=$(curl -s 'https://archlinux.org/mirrors/status/json/' | jq -r ".urls | .[] | select( .protocol == \"https\" and .isos == true ) | .url | \"-w \" + . + \"iso/${VERSION}/\"")

	echo 'Building torrent...'
	mktorrent \
		-l 19 \
		-c "Arch Linux ${VERSION} <https://archlinux.org>" \
		${httpmirrorlist} \
		-w "https://archive.archlinux.org/iso/${VERSION}/" \
		"archlinux-${VERSION}-x86_64.iso"

# upload artifacts
upload-release:
	rsync -cah --progress \
		"archlinux-${VERSION}-x86_64.iso"* "archlinux-x86_64.iso"* \
		"archlinux-bootstrap-${VERSION}-x86_64.tar.gz"* "archlinux-bootstrap-x86_64.tar.gz"*  \
		arch \
		sha256sums.txt b2sums.txt \
		-e ssh repos.archlinux.org:tmp/

# Publish uploaded release
publish:
	#!/usr/bin/env bash
	ssh -T repos.archlinux.org -- <<eot
		set -euo pipefail
		mkdir "/srv/ftp/iso/${VERSION}"

		pushd tmp
		mv \
		"archlinux-${VERSION}-x86_64.iso"* "archlinux-x86_64.iso"* \
		"archlinux-bootstrap-${VERSION}-x86_64.tar.gz"* "archlinux-bootstrap-x86_64.tar.gz"*  \
		arch \
		sha256sums.txt b2sums.txt \
		"/srv/ftp/iso/${VERSION}/"
		popd

		pushd /srv/ftp/iso/
		rm latest
		ln -s "${VERSION}" latest
		popd
	eot

# Remove specified release from server
remove-release version:
	ssh -T repos.archlinux.org -- rm -rf "/srv/ftp/iso/{{version}}"

# show release information
show-info:
	@file arch/boot/x86_64/vmlinuz-* | grep -P -o 'version [^-]*'
	@for sum in *sums.txt; do \
		echo -n "${sum%%sums.txt} "; \
		sed -zE "s/^([a-f0-9]+)\s+archlinux-${VERSION}-x86_64\.iso.*/\1\n/g" $sum; \
	done
	@echo GPG Fingerprint: "${GPGKEY}"
	@echo GPG Signer: "${GPGSENDER}"

# copy Torrent file to clipboard
copy-torrent:
	base64 "archlinux-${VERSION}-x86_64.iso.torrent" | xclip

# test the ISO image
run-iso:
	run_archiso -i "archlinux-${VERSION}-x86_64.iso"

# check mirror status for specified version or latest release
check-mirrors *version:
	@GODEBUG=netdns=go go run checkMirrors/main.go {{version}}

# vim: set ft=make :
