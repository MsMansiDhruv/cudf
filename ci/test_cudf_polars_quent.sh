#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Support invoking this script outside the repository root.
cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"/../

source rapids-datetime-string

# Maturin takes the wheel version from the static [project].version in pyproject.toml.
# Overwrite it so every build gets a unique version, matching the suffix used by the
# other wheels (see ci/build_wheel_common.sh).
RAPIDS_PACKAGE_VERSION="$(RAPIDS_VERSION_SUFFIX=".post${RAPIDS_DATETIME_STRING}" rapids-generate-version)"
sed -i "s/^version = .*/version = \"${RAPIDS_PACKAGE_VERSION}\"/" python/cudf_polars/quent/bridge/pyproject.toml

rapids-logger "Create cudf-polars Quent test environment"
. /opt/conda/etc/profile.d/conda.sh

ENV_YAML_DIR="$(mktemp -d)"

rapids-dependency-file-generator \
  --output conda \
  --file-key build_cudf_polars_quent \
  --matrix "cuda=${RAPIDS_CUDA_VERSION%.*};arch=$(arch);py=${RAPIDS_PY_VERSION}" | tee "${ENV_YAML_DIR}/env.yaml"

rapids-mamba-retry env create --yes -f "${ENV_YAML_DIR}/env.yaml" -n cudf_polars_quent

# Temporarily allow unbound variables for conda activation.
set +u
conda activate cudf_polars_quent
set -u

rapids-print-env

rapids-logger "Check cudf-polars-quent"
exec ./ci/run_cudf_polars_quent_tests.sh
