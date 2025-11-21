FROM docker.io/archlinux/archlinux:latest AS base

RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    --mount=type=cache,target=/var/lib/pacman/sync \
    pacman -Syu --noconfirm --needed archlinux-keyring

#bootc runtime + build deps
RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    --mount=type=cache,target=/var/lib/pacman/sync \
    pacman -Sy --noconfirm --needed \
    ostree \
    dracut

FROM base AS bootc-build

# bootc build deps
RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    --mount=type=cache,target=/var/lib/pacman/sync \
    pacman -Sy --noconfirm --needed base-devel git rust

RUN git clone --depth 1 "https://github.com/tgnthump/bootc.git" /tmp/bootc

ENV DESTDIR=/sysroot
RUN mkdir -p /sysroot

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    make -C /tmp/bootc bin install-all

FROM base AS final
COPY --from=bootc-build /sysroot/ /

#dracut runtime deps
RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    --mount=type=cache,target=/var/lib/pacman/sync \
    pacman -Sy --noconfirm --needed \
    linux \
    linux-firmware

# Regression with newer dracut broke this
ADD rootfs/usr/lib/dracut /usr/lib/dracut

# Recreate initramfs with dracut to ensure proper integration
RUN KERNEL_VERSION="$(ls -1 /usr/lib/modules | sort -V | tail -n 1)" && \
    dracut --force --no-hostonly --reproducible --zstd --verbose --kver "$KERNEL_VERSION" "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"

RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    --mount=type=cache,target=/var/lib/pacman/sync \
    pacman -Sy --noconfirm --needed \
    btrfs-progs e2fsprogs xfsprogs dosfstools fuse-overlayfs \
    skopeo \
    dbus \
    dbus-glib \
    glib2 \
    shadow \
    networkmanager \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack \
    wireplumber \
    openssh \
    man \
    nano \
    vim \
    wget \
    sudo \
    podman \
    just \
    git \
    hyprland \
    hyprpaper \
    hyprpicker \
    hyprlauncher \
    hypridle \
    hyprlock \
    hyprpolkitagent \
    dunst \
    qt5-wayland \
    qt6-wayland \
    waybar \
    nautilus \
    uwsm \
    libnewt \
    xdg-desktop-portal-hyprland \
    && pacman -Scc --noconfirm

RUN echo "KEYMAP=uk" > /etc/vconsole.conf

# Necessary for general behavior expected by image-based systems
RUN sed -i 's|^HOME=.*|HOME=/var/home|' "/etc/default/useradd" && \
    rm -rf /boot /home /root /usr/local /srv && \
    mkdir -p /var /sysroot /boot /usr/lib/ostree && \
    ln -s var/opt /opt && \
    ln -s var/roothome /root && \
    ln -s var/home /home && \
    ln -s sysroot/ostree /ostree && \
    echo "$(for dir in opt usrlocal home srv mnt ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a /usr/lib/tmpfiles.d/bootc-base-dirs.conf && \
    echo "d /var/roothome 0700 root root -" | tee -a /usr/lib/tmpfiles.d/bootc-base-dirs.conf && \
    echo "d /run/media 0755 root root -" | tee -a /usr/lib/tmpfiles.d/bootc-base-dirs.conf && \
    printf "[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n" | tee "/usr/lib/ostree/prepare-root.conf"

# Setup a temporary root passwd (changeme) for dev purposes
RUN usermod -p "$(echo "changeme" | mkpasswd -s)" root

RUN bootc container lint
RUN date > /build.time
