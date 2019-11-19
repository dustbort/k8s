#!/usr/bin/env bash

CHART=$1

# copy the values

mkdir ./values/$CHART
cp ./charts/$CHART/values.yaml ./values/$CHART/values.yaml