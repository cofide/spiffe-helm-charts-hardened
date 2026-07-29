#!/usr/bin/env bash

# Cofide: pull the private cofide/spire-server and cofide/spire-agent images once and
# `kind load` them directly into a cluster's nodes, instead of letting each node pull
# them live from ECR. A live per-node pull has been observed to occasionally take
# minutes instead of seconds, which can blow through a `helm --wait` timeout. This is
# called once per kind cluster created in CI (the main cluster, plus any additional
# "child"/"other" clusters an example's run-tests.sh creates).
#
# The image refs are read from the charts' values.yaml so this stays in sync with
# whatever cofide/spire-server and cofide/spire-agent versions the charts default to.

set -euo pipefail

SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
REPO_ROOT="$(dirname "${SCRIPTPATH}")/.."

CLUSTER_NAME="${1:?usage: load-spire-images.sh <kind-cluster-name>}"

image_ref() {
  local values_file="$1"
  local registry repository tag
  registry="$(yq e '.image.registry' "${values_file}")"
  repository="$(yq e '.image.repository' "${values_file}")"
  tag="$(yq e '.image.tag' "${values_file}")"
  if [[ -z "${tag}" || "${tag}" == "null" ]]; then
    tag="$(yq e '.appVersion' "$(dirname "${values_file}")/Chart.yaml")"
  fi
  echo "${registry}/${repository}:${tag}"
}

SPIRE_SERVER_IMAGE="$(image_ref "${REPO_ROOT}/charts/spire/charts/spire-server/values.yaml")"
SPIRE_AGENT_IMAGE="$(image_ref "${REPO_ROOT}/charts/spire/charts/spire-agent/values.yaml")"

# Cofide: pin to the daemon's own platform throughout. On a Docker daemon using the
# containerd image store, a plain `docker pull`/`docker save` (no --platform) keeps the
# full multi-arch manifest list even though only one platform's layers get downloaded.
# `kind load image-archive` then runs `ctr images import --all-platforms`, which tries
# to import every platform in that manifest and fails with "content digest ... not
# found" (surfaced by kind as "failed to detect containerd snapshotter") for the
# platforms whose layers were never actually pulled. Restricting both the pull and the
# save to a single platform keeps the manifest and the archive's contents consistent.
PLATFORM="$(docker version --format '{{.Server.Os}}/{{.Server.Arch}}')"

docker pull --platform "${PLATFORM}" "${SPIRE_SERVER_IMAGE}"
docker pull --platform "${PLATFORM}" "${SPIRE_AGENT_IMAGE}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

docker save --platform "${PLATFORM}" "${SPIRE_SERVER_IMAGE}" "${SPIRE_AGENT_IMAGE}" -o "${TMPDIR}/spire-images.tar"
kind load image-archive "${TMPDIR}/spire-images.tar" --name "${CLUSTER_NAME}"
