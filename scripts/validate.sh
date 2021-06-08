#!/bin/bash

export IFS="
"
for i in $(find . -name "*.json"); do
	if jq -e . "$i" >/dev/null; then
		echo "Valid:   $i";
	else
		echo "Invalid: $i";
	fi
done
