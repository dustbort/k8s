#!/usr/bin/env bash

CHART=$1

# download the chart
helm fetch \
  --repo https://kubernetes-charts.storage.googleapis.com \
  --untar \
  --untardir ./charts \
  $CHART