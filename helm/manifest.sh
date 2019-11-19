#!/usr/bin/env bash

CHART=$1
RELEASE_NAME=$2
NAMESPACE=$3

# render the manifest from the template by applying the values

helm template $RELEASE_NAME ./charts/$CHART \
  --values ./values/$CHART/values.yaml \
  --output-dir ./manifests \
  --namespace $NAMESPACE
