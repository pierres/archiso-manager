VENDOR := $(CURDIR)/vendor
VERSION := $(shell date +%Y.%m.%d)
GPGKEY := 4AA4767BBC9C4B1D18AE28B77F2D434B9741E8AC

all: build-iso build-netboot build-bootstrap create-signatures create-torrent create-zsync-control show-info

clean:
	git clean -xdf -e .idea -e codesign.crt -e codesign.key

build-iso:
	$(eval TMPDIR := $(shell mktemp -d))
	@echo "Set an empty password on the temporary copy of the GPG key"
	gpg --use-agent --export-secret-keys $(GPGKEY) > $(TMPDIR)/gpgkey
	GNUPGHOME=$(TMPDIR)/.gnupg gpg --import $(TMPDIR)/gpgkey
	GNUPGHOME=$(TMPDIR)/.gnupg gpg --change-passphrase $(GPGKEY)
	(cd $(TMPDIR) && sudo GNUPGHOME=$(TMPDIR)/.gnupg mkarchiso -g $(GPGKEY) /usr/share/archiso/configs/releng/)
	cp $(TMPDIR)/out/archlinux-$(VERSION)-x86_64.iso .
	sudo rm -rf $(TMPDIR)

build-netboot:
	bsdtar -x --exclude=arch/boot/syslinux \
		--exclude 'memtest*' --exclude 'pkglist.*' \
		-f archlinux-$(VERSION)-x86_64.iso \
		arch/
	find arch -type d -exec chmod 0755 {} \;
	find arch -type f -exec chmod 0644 {} \;
	for f in arch/boot/amd-ucode.img arch/boot/intel-ucode.img arch/boot/x86_64/vmlinuz-* arch/boot/x86_64/initramfs-*.img; do \
		$(VENDOR)/arch_netboot_tools/codesigning/sign_file.sh $$f \
			$(CURDIR)/codesign.crt \
			$(CURDIR)/codesign.key; \
	done

build-bootstrap:
	sudo $(VENDOR)/genbootstrap/genbootstrap

create-signatures:
	for f in archlinux-$(VERSION)-x86_64.iso archlinux-bootstrap-$(VERSION)-x86_64.tar.gz; do \
		gpg --use-agent --detach-sign $$f; \
	done
	sha1sum archlinux-$(VERSION)-x86_64.iso archlinux-bootstrap-$(VERSION)-x86_64.tar.gz > sha1sums.txt
	md5sum archlinux-$(VERSION)-x86_64.iso archlinux-bootstrap-$(VERSION)-x86_64.tar.gz > md5sums.txt

create-torrent:
	$(VENDOR)/archlinux-torrent-utils/mktorrent-archlinux $(VERSION) archlinux-$(VERSION)-x86_64.iso

create-zsync-control:
	zsyncmake -C -u archlinux-$(VERSION)-x86_64.iso archlinux-$(VERSION)-x86_64.iso

upload-release:
	rsync -cah --progress \
		archlinux-$(VERSION)-x86_64.iso* md5sums.txt sha1sums.txt arch archlinux-bootstrap-$(VERSION)-x86_64.tar.gz* \
		-e ssh repos.archlinux.org:tmp/

show-info:
	@file arch/boot/x86_64/vmlinuz-* | grep -P -o 'version [^-]*'
	@grep archlinux-$(VERSION)-x86_64.iso sha1sums.txt
	@grep archlinux-$(VERSION)-x86_64.iso md5sums.txt
	@echo GPG Fingerprint: ${GPGKEY}

copy-torrent:
	base64 archlinux-$(VERSION)-x86_64.iso.torrent | xclip

run-iso:
	qemu-system-x86_64 -boot d -m 4G -enable-kvm -device intel-hda -device hda-duplex -smp cores=2,threads=2 -cdrom archlinux-$(VERSION)-x86_64.iso

.PHONY: all clean build-iso build-netboot build-bootstrap create-signatures create-torrent create-zsync-control upload-release show-info copy-torrent run-iso
