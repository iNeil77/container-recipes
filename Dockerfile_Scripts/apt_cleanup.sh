#!/usr/bin/env bash
# Dockerfile_Scripts/apt_cleanup.sh
set -euo pipefail

apt-get autoremove -yqq
apt-get clean
rm -rf \
    /var/lib/apt/lists/* \
    /var/cache/apt/archives/*.deb \
    /var/cache/apt/archives/partial/* \
    /var/cache/apt/*.bin \
    /tmp/* \
    /var/tmp/* \
    /usr/share/man/?? \
    /usr/share/man/??_* \
    /root/.gnupg
