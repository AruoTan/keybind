ARG BASE_IMAGE=aruowis-dev-base:1
FROM ${BASE_IMAGE}

USER root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       binutils-mingw-w64-x86-64 ca-certificates curl file fonts-dejavu-core \
       gcc-mingw-w64-x86-64-posix python3 unzip wine64 xauth xvfb zip \
    && rm -rf /var/lib/apt/lists/*

COPY --chown=vscode:vscode scripts/setup_tools.py scripts/toolchain.json /tmp/keybind-devcontainer/scripts/
COPY --chown=vscode:vscode scripts/build_tools/__init__.py scripts/build_tools/toolchain.py /tmp/keybind-devcontainer/scripts/build_tools/
USER vscode
ENV PATH="/home/vscode/.cargo/bin:${PATH}"
RUN python3 /tmp/keybind-devcontainer/scripts/setup_tools.py
