ARG BASE_IMAGE=aruowis-dev-base:1
FROM ${BASE_IMAGE}

USER root
COPY scripts/install-system.sh /tmp/keybind-devcontainer/scripts/install-system.sh
RUN bash /tmp/keybind-devcontainer/scripts/install-system.sh

COPY --chown=vscode:vscode toolchain.json /tmp/keybind-devcontainer/toolchain.json
COPY --chown=vscode:vscode scripts/setup-tools.sh /tmp/keybind-devcontainer/scripts/setup-tools.sh
USER vscode
ENV PATH="/home/vscode/.cargo/bin:${PATH}"
RUN bash /tmp/keybind-devcontainer/scripts/setup-tools.sh
