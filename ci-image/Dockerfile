# The CI image of the dvv Linux jobs (dvv-ci.yml). Inputs: everything in ci-image/, plus
# tools/requirements.txt and tools/ci-image-inputs.cmake. Published by ci-image.yml through build.sh.

# Before the first FROM, so that both stages see them.
# The Ubuntu archive as of this moment (snapshot.ubuntu.com): the inputs fix every package version.
ARG UBUNTU_SNAPSHOT=20261119T095545Z
# The Python build that actions/setup-python installs (actions/python-versions).
ARG PYTHON_VERSION=3.13.18
ARG PYTHON_URL=https://github.com/actions/python-versions/releases/download/3.13.18-40336726450/python-3.13.18-linux-24.04-x64.tar.gz
ARG PYTHON_SHA256=683005a1465d94d40045f6a1a6eb316885b5f08d3360f7922b44ef58a14a9eed
# The pip that setup.sh's own upgrade installs: the version ensurepip bundles with PYTHON_VERSION.
ARG PIP_VERSION=26.2.2

# The noble image (index digest) at the snapshot date, shared by both stages.
FROM ubuntu:24.04@sha256:73b999393d07f2bf65a40373778a44dc9a6d54ad7718d29247d8ff9413c4d6a8 AS base

# Python download: curl from the snapshot, the archive checked against its SHA256. Only the archive
# and the CA bundle reach the final stage (bind mounts), so curl stays out of the image.
# CA bootstrap: snapshot.ubuntu.com is HTTPS only and the bare base has no CA bundle, so this stage's
# own CA bundle is apt-signature-checked from the base's archive; nothing from it lands in the image.
FROM base AS download
ARG UBUNTU_SNAPSHOT
ARG PYTHON_URL
ARG PYTHON_SHA256
RUN apt-get update -o Acquire::Retries=5 \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -o Acquire::Retries=5 ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && apt-get update --snapshot "$UBUNTU_SNAPSHOT" -o Acquire::Retries=5 \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --snapshot "$UBUNTU_SNAPSHOT" \
      -o Acquire::Retries=5 curl \
 && curl -fsSL --retry 5 --retry-all-errors "$PYTHON_URL" -o /python.tgz \
 && echo "$PYTHON_SHA256  /python.tgz" | sha256sum -c -

FROM base
ARG UBUNTU_SNAPSHOT
ARG PYTHON_VERSION
ARG PIP_VERSION
ARG DVV_CI_IMAGE_INPUTS
ARG DVV_CI_IMAGE_SOURCE
LABEL dvv.ci-image.inputs=$DVV_CI_IMAGE_INPUTS org.opencontainers.image.source=$DVV_CI_IMAGE_SOURCE
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
COPY ci-image/packages.txt tools/requirements.txt /tmp/dvv-ci-image/
# apt-install <group>: installs one "## <group>" of packages.txt from the snapshot, with recommends
# as `apt-get install -y` does, and deletes the apt lists again, so that no layer keeps them. Until
# the base group has installed ca-certificates, apt verifies the snapshot with the download stage's
# CA bundle, mounted at /run/dvv-ci-image/ca.crt for that RUN only.
COPY --chmod=755 <<'EOF' /tmp/dvv-ci-image/apt-install
#!/bin/sh
set -eu
packages=$(awk -v group="$1" '$0 == "## " group { on = 1; next } /^## / { on = 0 }
                              on && !/^#/ && NF { print $1 }' /tmp/dvv-ci-image/packages.txt)
if [ -z "$packages" ]; then
  echo "apt-install: no group '$1' in packages.txt" >&2
  exit 1
fi
set -- --snapshot "$UBUNTU_SNAPSHOT" -o Acquire::Retries=5
if [ -e /run/dvv-ci-image/ca.crt ]; then
  set -- "$@" -o Acquire::https::CaInfo=/run/dvv-ci-image/ca.crt
fi
apt-get update "$@"
# shellcheck disable=SC2086 # one word per package
apt-get install -y "$@" $packages
rm -rf /var/lib/apt/lists/*
EOF
# One RUN per group of packages.txt, so they become separate layers that download in parallel.
RUN --mount=type=bind,from=download,source=/etc/ssl/certs/ca-certificates.crt,target=/run/dvv-ci-image/ca.crt \
    /tmp/dvv-ci-image/apt-install base
RUN /tmp/dvv-ci-image/apt-install compiler
RUN /tmp/dvv-ci-image/apt-install gui
RUN /tmp/dvv-ci-image/apt-install display-vulkan \
 && mkdir -p /etc/dvv-ci-image \
 && dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort \
      > /etc/dvv-ci-image/packages.lock
# Python: the archive's own setup.sh with RUNNER_TOOL_CACHE=/opt/hostedtoolcache (the python link,
# ensurepip), exactly as setup-python installs it. PIP_CONSTRAINT pins setup.sh's
# `pip install --upgrade --force-reinstall pip` to PIP_VERSION, not PyPI's newest. Then the pinned
# tools, and `pip freeze --all` (pip included) into pip.lock.
RUN --mount=type=bind,from=download,source=/python.tgz,target=/tmp/python.tgz <<'EOF'
set -eu
export PIP_CONSTRAINT=/tmp/dvv-ci-image/pip-constraint.txt PIP_NO_CACHE_DIR=1 \
       PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_ROOT_USER_ACTION=ignore
echo "pip==$PIP_VERSION" > "$PIP_CONSTRAINT"
mkdir /tmp/python
tar -xzf /tmp/python.tgz -C /tmp/python
(cd /tmp/python && RUNNER_TOOL_CACHE=/opt/hostedtoolcache bash ./setup.sh)
rm -rf /tmp/python
python=/opt/hostedtoolcache/Python/$PYTHON_VERSION/x64/bin/python
pip_version=$("$python" -m pip --version)
case $pip_version in
  "pip $PIP_VERSION from "*) ;;
  *) echo "python -m pip --version is '$pip_version', not pip $PIP_VERSION" >&2; exit 1 ;;
esac
"$python" -m pip install --no-cache-dir --retries 10 --timeout 60 -r /tmp/dvv-ci-image/requirements.txt
"$python" -m pip freeze --all > /etc/dvv-ci-image/pip.lock
EOF
# The environment setup-python exports today (find-python.ts:151-174).
ENV pythonLocation=/opt/hostedtoolcache/Python/$PYTHON_VERSION/x64
ENV Python_ROOT_DIR=$pythonLocation Python2_ROOT_DIR=$pythonLocation \
    Python3_ROOT_DIR=$pythonLocation PKG_CONFIG_PATH=$pythonLocation/lib/pkgconfig \
    LD_LIBRARY_PATH=$pythonLocation/lib PATH=$pythonLocation/bin:$pythonLocation:$PATH
# machine-id: a package's postinst writes a random one; it is replaced by the first 32 hex digits of
# the inputs hash, so that the image stays a function of its inputs (the dbus link follows it).
# The /tmp/dvv-ci-image helpers are removed last, after the environment hash.
RUN groupadd --gid 1001 runner && useradd --uid 1001 --gid 1001 --create-home runner \
 && mkdir -m 1777 /tmp/.X11-unix \
 && printf '%.32s\n' "$DVV_CI_IMAGE_INPUTS" > /etc/machine-id \
 && mkdir -p /var/lib/dbus && ln -sf /etc/machine-id /var/lib/dbus/machine-id \
 && printf '%s\n' "$DVV_CI_IMAGE_INPUTS" > /etc/dvv-ci-image/inputs.sha256 \
 && cat /etc/dvv-ci-image/packages.lock /etc/dvv-ci-image/pip.lock | sha256sum | cut -c1-64 \
      > /etc/dvv-ci-image/environment.sha256 \
 && rm -rf /tmp/dvv-ci-image
# No USER and no WORKDIR (GitHub's Dockerfile guidance); the job sets the user (dvv-ci.yml).
