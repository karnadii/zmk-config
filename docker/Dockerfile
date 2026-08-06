# Local build toolchain for the Geulis keyboard ZMK config.
#
# Strategy: reuse the upstream ZMK ARM build image (`zmkfirmware/zmk-build-arm:stable`)
# – it's the exact image ZMK's GitHub Actions uses for Zephyr 3.5 / ZMK v0.3 builds.
# Mount this repo as a workspace, run `west init` + `west update` once (or whenever
# west modules change), then `west build` per entry in build.yaml.
#
# This Dockerfile is a thin wrapper that pre-installs the western CLI (python -m west)
# and `yq` for parsing build.yaml. It inherits from the upstream image so we don't
# have to rebuild the GNU Arm toolchain / Zephyr SDK ourselves.
FROM zmkfirmware/zmk-build-arm:stable

ARG DEBIAN_FRONTEND=noninteractive

# west itself is bundled with the base image (it ships west in /usr/local/bin).
# Add yq for parsing build.yaml and a couple of utilities for convenience.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        graphviz \
        python3-pip \
    && rm -rf /var/lib/apt/lists/*

# yq (mikefarah's Go implementation – the same one ZMK's CI downloads on the fly)
ARG YQ_VERSION=v4.40.5
RUN curl -fsSLo /usr/local/bin/yq \
        https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 && \
    chmod +x /usr/local/bin/yq

# Make the workspace the default working directory.
WORKDIR /workspace

# Pre-create the scratch west-workspace directory with world-writable perms
# so a `user:` override in docker-compose can write to the named volume
# (Docker creates named volumes as root by default).
RUN mkdir -p /zmk-workspace && chmod 777 /zmk-workspace

# Default to an interactive bash shell so `docker compose run build bash` feels natural.
CMD ["bash"]
