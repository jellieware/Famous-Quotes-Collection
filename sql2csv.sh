#!/usr/bin/env bash

# convert sql dumps to csv, tsv, ssv...
# also can filter fields using a sed pattern
# only works on linux

function usage
{
  echo "usage: $0 [-sc CORES] [-o OUTFILE] [-p PATTERN] SQLFILE" 2>&1 && exit 1
}

while getopts ":c:p:o:s" opt; do
  case "$opt" in
    c)
      c="$OPTARG"
      ;;
    p)
      p="$OPTARG"
      ;;
    o)
      o="$OPTARG"
      ;;
    s)
      s=1
      ;;
    *)
      usage
      ;;
  esac
done
shift $(( OPTIND - 1 ))

CORES=${c:-$(grep -c processor /proc/cpuinfo)}
PATTERN=${p:-''}
OUTFILE="$o"
SILENT=$s

if [[ ! $1 ]]; then
  usage
elif [[ ! -f $1 ]]; then
  echo "unable to open file '$1'" 2>&1 && exit 1
fi

if [[ $SILENT ]]; then
  LOGDEV=/dev/null
else
  LOGDEV=/dev/stderr
fi

TEMP_DIR=$(mktemp -d)
OUT_DIR=$(mktemp -d)

echo "Splitting..." >"$LOGDEV"

csplit -sn 4 -f "$TEMP_DIR/" "$1" "%^INSERT%" "/^INSERT/" "{*}"
for part in $TEMP_DIR/*; do
  number=$(( 10#$(basename $part) ))
  (( core = number % CORES ))
  parts[$core]+="$part "
done

echo "Converting..." >"$LOGDEV"

core=1
for files in "${parts[@]}"; do
  cat $files \
  | sed -n '/^INSERT/p' \
  | sed -r 's/^[^(]+\((.*)\);$/\1/' \
  | sed 's/),(/\
/g' \
  | sed -r "$PATTERN" \
  >"$OUT_DIR/$core" &
  processes[$core]=$!
  (( core += 1 ))
done
for process_id in "${processes[@]}"; do
  wait $process_id
done

echo "Combining..." >"$LOGDEV"

if [[ $OUTFILE ]]; then
  cat $OUT_DIR/* >"$OUTFILE"
else
  cat $OUT_DIR/*
fi

rm -rf $TEMP_DIR $OUT_DIR

echo "Success!" >"$LOGDEV"
