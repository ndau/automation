#!/bin/bash
# displays chain height for a noms database.
dir=$1
b36=$(noms show ${dir}::ndau.value.Height | tr -d '"')
echo $((36#$b36))
