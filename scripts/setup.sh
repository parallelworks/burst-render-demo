#!/bin/bash
# setup.sh — Controller-side setup (runs before start scripts)
# Verifies dependencies and bootstraps uv package manager.

set -e

echo "=========================================="
echo "Burst Renderer Setup: $(date)"
echo "=========================================="
echo "Hostname: $(hostname)"
echo "Job dir:  ${PW_PARENT_JOB_DIR:-$(pwd)}"

JOB_DIR="${PW_PARENT_JOB_DIR%/}"

# =============================================================================
# Verify Python
# =============================================================================
PYTHON_CMD=""
for cmd in python3 python; do
    command -v $cmd &>/dev/null && { PYTHON_CMD=$cmd; break; }
done

if [ -z "${PYTHON_CMD}" ]; then
    echo "[ERROR] Python not found in PATH"
    echo "  Searched: python3, python"
    echo "  PATH=${PATH}"
    exit 1
fi

PYTHON_VERSION=$(${PYTHON_CMD} --version 2>&1)
echo "Python: ${PYTHON_CMD} (${PYTHON_VERSION})"

# =============================================================================
# Bootstrap uv (fast Python package manager)
#
# uv is installed to a SHARED user-level cache so it's downloaded once per
# host instead of once per job per host. On compute sites where many jobs
# run over time, this saves ~35 MB per job. Falls back to the job dir if
# the shared location isn't writable (read-only HOME, etc.).
# =============================================================================
SHARED_UV_ROOT="${BURST_RENDER_UV_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/burst-render}"
SHARED_UV_DIR="${SHARED_UV_ROOT}/uv"
SHARED_UV_BIN="${SHARED_UV_DIR}/uv"

if mkdir -p "${SHARED_UV_DIR}" 2>/dev/null && [ -w "${SHARED_UV_DIR}" ]; then
    UV_DIR="${SHARED_UV_DIR}"
    UV_BIN="${SHARED_UV_BIN}"
    UV_LOCATION="shared"
else
    UV_DIR="${JOB_DIR}/.uv"
    UV_BIN="${UV_DIR}/uv"
    UV_LOCATION="job-local (shared cache not writable)"
    mkdir -p "${UV_DIR}"
fi

install_uv() {
    if [ -x "${UV_BIN}" ]; then
        echo "uv: ${UV_BIN} (${UV_LOCATION}, cached: $(${UV_BIN} --version 2>&1))"
        return 0
    fi

    echo "Installing uv to ${UV_DIR} (${UV_LOCATION})..."

    # Try downloading uv standalone binary
    local arch
    arch=$(uname -m)
    case "${arch}" in
        x86_64)  arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        *)
            echo "  [WARN] Unsupported architecture: ${arch}, skipping uv install"
            return 1
            ;;
    esac

    local url="https://github.com/astral-sh/uv/releases/latest/download/uv-${arch}-unknown-linux-gnu.tar.gz"

    # Atomic install: extract to a temp dir under the same parent, then
    # mv the binary into place (rename is atomic on the same filesystem).
    # Concurrent installers either both finish the mv (last writer wins,
    # binary is identical) or one loses the race harmlessly.
    local tmp_dir
    tmp_dir=$(mktemp -d "${UV_DIR}/.install.XXXXXX" 2>/dev/null) || {
        echo "  [WARN] Could not create temp install dir under ${UV_DIR}"
        return 1
    }
    # Clean up tmp on any exit from this function
    trap "rm -rf '${tmp_dir}'" RETURN

    if command -v curl &>/dev/null; then
        curl -fsSL "${url}" | tar -xz -C "${tmp_dir}" --strip-components=1 2>/dev/null
    elif command -v wget &>/dev/null; then
        wget -qO- "${url}" | tar -xz -C "${tmp_dir}" --strip-components=1 2>/dev/null
    else
        echo "  [WARN] Neither curl nor wget available, skipping uv install"
        return 1
    fi

    if [ ! -x "${tmp_dir}/uv" ]; then
        echo "  [WARN] uv download failed (no internet?), will fall back to pip"
        return 1
    fi

    # If a concurrent installer already populated UV_BIN, theirs is fine.
    if [ -x "${UV_BIN}" ]; then
        echo "  uv: ${UV_BIN} (installed concurrently by another job)"
        return 0
    fi

    mv "${tmp_dir}/uv" "${UV_BIN}" 2>/dev/null || {
        # Race lost between -x check and mv — accept whichever copy won.
        if [ -x "${UV_BIN}" ]; then
            echo "  uv: ${UV_BIN} (installed concurrently)"
            return 0
        fi
        echo "  [WARN] Failed to install uv binary to ${UV_BIN}"
        return 1
    }

    echo "  uv installed: $(${UV_BIN} --version 2>&1)"
    return 0
}

if install_uv; then
    echo "${UV_BIN}" > "${JOB_DIR}/UV_PATH"
fi

# Mark setup complete
touch "${JOB_DIR}/SETUP_COMPLETE"
echo "Setup complete!"
