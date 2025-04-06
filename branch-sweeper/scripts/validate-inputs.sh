#!/bin/bash

if [[ ! "$1" =~ ^[0-9]+$ ]]; then
  echo "::error::weeks_threshold must be a positive number"
  exit 1
fi