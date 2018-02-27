#!/bin/bash

BIN_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

. $BIN_DIR/load-env.sh


# stop if any command fails
set -e

# TODO check if table is empty
if [[ $($FLUO_CMD scan -a $FLUO_APP_NAME | head)  = *[![:space:]]* ]]; then
  echo "ERROR Table is not empty."
  exit 1
fi

echo "Removing any previous logs in $LOG_DIR"
mkdir -p $LOG_DIR
rm -f $LOG_DIR/*

hadoop fs -rm -r -f /stresso/

set -e

if (( GEN_INIT > 0 )); then
  # generate and load intial data using map reduce writing directly to table
  echo "*****Generating and loading initial data set*****"
  $BIN_DIR/generate.sh $MAPS $((GEN_INIT / MAPS)) $MAX /stresso/init >$LOG_DIR/generate_0.out 2>$LOG_DIR/generate_0.err
  $BIN_DIR/init.sh /stresso/init /stresso/initTmp $REDUCES >$LOG_DIR/init.out 2>$LOG_DIR/init.err
  hadoop fs -rm -r /stresso/initTmp
fi

# load data incrementally
START_TIME=`date +%s`
i=1
while [ $(( $(date +%s) - $LOAD_TIME )) -lt $START_TIME ]; do
   echo "*****Generating and loading incremental data set $i*****"
  $BIN_DIR/generate.sh $MAPS $((GEN_INCR / MAPS)) $MAX /stresso/$i >$LOG_DIR/generate_$i.out 2>$LOG_DIR/generate_$i.err
  $BIN_DIR/load.sh /stresso/$i >$LOG_DIR/load_$i.out 2>$LOG_DIR/load_$i.err
  # TODO could reload the same dataset sometimes, maybe when i%5 == 0 or something
  $BIN_DIR/compact-ll.sh $MAX $COMPACT_CUTOFF >$LOG_DIR/compact-ll_$i.out 2>$LOG_DIR/compact-ll_$i.err
  if ! ((i % WAIT_PERIOD)); then
    $FLUO_CMD wait -a $FLUO_APP_NAME >$LOG_DIR/wait_$i.out 2>$LOG_DIR/wait_$i.err
  else
    sleep $SLEEP
  fi

  i=$((i+1))
done

# print unique counts
echo "*****Calculating # of unique integers using MapReduce*****"
$BIN_DIR/unique.sh $REDUCES /stresso/* >$LOG_DIR/unique.out 2>$LOG_DIR/unique.err
grep UNIQUE $LOG_DIR/unique.err

echo "*****Wait for Fluo to finish processing*****"
$FLUO_CMD wait -a $FLUO_APP_NAME

echo "*****Printing # of unique integers calculated by Fluo*****"
$BIN_DIR/print.sh >$LOG_DIR/print.out 2>$LOG_DIR/print.err
cat $LOG_DIR/print.out

echo "*****Verifying Fluo & MapReduce results match*****"
MAPR_TOTAL=`grep UNIQUE $LOG_DIR/unique.err | cut -d = -f 2`
FLUO_TOTAL=`grep "Total at root" $LOG_DIR/print.out | cut -d ' ' -f 5`
if [ $MAPR_TOTAL -eq $FLUO_TOTAL ]; then
  echo "Success! Fluo & MapReduce both calculated $FLUO_TOTAL unique integers"
  exit 0
else
  echo "ERROR - Results do not match. Fluo calculated $FLUO_TOTAL unique integers while MapReduce calculated $MAPR_TOTAL integers"
  exit 1
fi
