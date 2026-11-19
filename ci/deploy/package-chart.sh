#!/usr/bin/env bash
# Package helm/openg2p-cropsown-registry with this build's images into built-chart/, with
# scripts/ci/package_chart.py of oan-helm. The deploy installs that archive and publish-chart.sh
# publishes the same file. chart-images.tsv comes from the Build & Push stage.
#
# When this build built the dashboard UI (dashboardUi.image in chart-images.tsv) and the dashboard may be deployed on
# dev (ci/deploy/oan-chart.json dashboard.promotionReady), the pinned dashboard chart (verified by its checksum) is
# packaged the same way into built-chart/dashboard/, with its dev values beside it: the deploy installs that archive
# (ci/dashboard/deploy-ui.sh) and publish-chart.sh publishes it after. A dashboard that is held back is not packaged,
# so nothing that New Dev does not run is published.
set -euo pipefail
: "${BRANCH_NAME:?Jenkins sets the branch}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git clone --quiet --depth 1 --filter=blob:none --sparse \
  https://github.com/Centre-for-Open-Societal-Systems/oan-helm.git "$WORK/oan-helm"
git -C "$WORK/oan-helm" sparse-checkout set scripts/ci
python3 "$WORK/oan-helm/scripts/ci/package_chart.py" \
  --chart helm/openg2p-cropsown-registry --images chart-images.tsv --output built-chart \
  --source-repository Centre-for-Open-Societal-Systems/cropsown-regsitry \
  --source-commit "$(git rev-parse HEAD)" --subject "$(git log -1 --pretty=%s)" \
  --release cropsown-registry --namespace crop \
  --overlay environments/dev/values/cropsown.yaml --branch "$BRANCH_NAME"

awk -F'\t' -v OFS='\t' '$1 == "dashboardUi.image" { $1 = "image"; print }' chart-images.tsv > "$WORK/dashboard-images.tsv"
if [ -s "$WORK/dashboard-images.tsv" ] && [ "$(python3 ci/deploy/oan_chart.py is-deployable dashboard dev)" = "true" ]; then
  archive=$(python3 ci/deploy/oan_chart.py fetch dashboard "$WORK/central")
  name=$(python3 -c 'import json; print(json.load(open("ci/deploy/oan-chart.json"))["dashboard"]["name"])')
  overlay=$(python3 -c 'import json; print(json.load(open("ci/deploy/oan-chart.json"))["dashboard"]["values"]["path"])')
  mkdir -p "$WORK/source"
  tar -xzf "$archive" -C "$WORK/source"
  python3 "$WORK/oan-helm/scripts/ci/package_chart.py" \
    --chart "$WORK/source/$name" --images "$WORK/dashboard-images.tsv" --output built-chart/dashboard \
    --source-repository Centre-for-Open-Societal-Systems/cropsown-regsitry \
    --source-commit "$(git rev-parse HEAD)" --subject "$(git log -1 --pretty=%s)" \
    --release "$name" --namespace crop --overlay "$overlay" --branch "$BRANCH_NAME"
  python3 ci/deploy/oan_chart.py values dashboard built-chart/dashboard/values.yaml > /dev/null
fi
