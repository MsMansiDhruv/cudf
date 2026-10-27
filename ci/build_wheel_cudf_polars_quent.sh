#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Support invoking this script outside the repository root.
cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"/../

# shellcheck source=ci/build_wheel_common.sh
source ./ci/build_wheel_common.sh

readonly RUST_VERSION=1.97
readonly RUSTUP_VERSION=1.29.2
export RUSTUP_HOME="${RUSTUP_HOME:-/tmp/rustup}"
export CARGO_HOME="${CARGO_HOME:-/tmp/cargo}"
export CARGO_INCREMENTAL="${CARGO_INCREMENTAL:-0}"
export PATH="${CARGO_HOME}/bin:${PATH}"

case "$(uname -m)" in
  x86_64)
    rustup_target=x86_64-unknown-linux-gnu
    rustup_sha256=5be191e8c70a5007074254cb74d78dbfdd25cd5a61c27de7b8e5410122ec24f4
    ;;
  aarch64)
    rustup_target=aarch64-unknown-linux-gnu
    rustup_sha256=a9c168dbea81a84671c6b7a5c1795cb0eb699020110d107ddfca427bd797e697
    ;;
  *)
    echo "Unsupported architecture for rustup: $(uname -m)" >&2
    exit 1
    ;;
esac

rustup_init="$(mktemp)"
rapids-retry curl --proto '=https' --tlsv1.2 --silent --show-error --fail \
  "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${rustup_target}/rustup-init" \
  --output "${rustup_init}"
printf '%s  %s\n' "${rustup_sha256}" "${rustup_init}" | sha256sum --check --status -
chmod +x "${rustup_init}"
"${rustup_init}" \
  -y \
  --no-modify-path \
  --profile minimal \
  --default-toolchain "${RUST_VERSION}" \
  -c rustfmt \
  -c clippy
rm -f "${rustup_init}"

export RAPIDS_PACKAGE_VERSION
RAPIDS_PACKAGE_VERSION=$(<VERSION)
export CUDF_POLARS_QUENT_USE_RAPIDS_BUILD=true
# shellcheck source=ci/run_cudf_polars_quent_tests.sh
source ./ci/run_cudf_polars_quent_tests.sh

mkdir -p "${RAPIDS_WHEEL_BLD_OUTPUT_DIR}"
python -m auditwheel repair \
  -w "${RAPIDS_WHEEL_BLD_OUTPUT_DIR}" \
  python/cudf_polars/quent/bridge/dist/*

shopt -s nullglob
generated_wheels=("${RAPIDS_WHEEL_BLD_OUTPUT_DIR}"/*.whl)
shopt -u nullglob
if ((${#generated_wheels[@]} != 1)); then
  echo "Expected exactly one generated Quent wheel, found ${#generated_wheels[@]}" >&2
  exit 1
fi
if [[ "$(basename "${generated_wheels[0]}")" != *-cp312-abi3-*.whl ]]; then
  echo "Expected a cp312-abi3 wheel, found ${generated_wheels[0]}" >&2
  exit 1
fi

./ci/validate_wheel.sh \
  python/cudf_polars/quent/bridge \
  "${RAPIDS_WHEEL_BLD_OUTPUT_DIR}" \
  10M

export RAPIDS_PACKAGE_NAME
RAPIDS_PACKAGE_NAME="$(rapids-artifact-name wheel_python cudf-polars-quent cudf --stable)"
