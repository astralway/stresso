#!/bin/bash

BIN_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

#TODO maybe have a single skip checks var
SKIP_JAR_CHECKS=1
SKIP_FLUO_PROPS_CHECK=1
. $BIN_DIR/load-env.sh

cd $BIN_DIR/..

# stop if any command fails
set -e

# Build jar and shaded jar
mvn clean package dependency:copy-dependencies \
     -DincludeArtifactIds=fluo-recipes-core \
     -Dfluo.version=$FLUO_VERSION \
     -Daccumulo.version=$ACCUMULO_VERSION
mkdir target/lib
cp target/stresso-0.0.1-SNAPSHOT.jar target/dependency/*.jar target/lib

# Create config file used for fluo initialization
cp $FLUO_HOME/conf/fluo-app.properties ./conf/fluo-app.properties
$SED '/fluo.worker.num.threads.*/d' ./conf/fluo-app.properties
cat << EOF >> ./conf/fluo-app.properties
fluo.observer.init.dir=$(pwd)/target/lib
fluo.observer.0=stresso.trie.NodeObserver
fluo.worker.num.threads=128
fluo.loader.num.threads=128
fluo.loader.queue.size=128
fluo.app.trie.nodeSize=8
fluo.app.trie.stopLevel=$STOP
EOF

# Initialize Stresso
fluo init -a $FLUO_APP_NAME -p conf/fluo-app.properties -f

# Optimize Accumulo table used by Fluo Stresso Application
accumulo shell -u root -p secret <<EOF
config -t $FLUO_APP_NAME -s table.custom.balancer.group.regex.pattern=(\\\\d\\\\d).*
config -t $FLUO_APP_NAME -s table.custom.balancer.group.regex.default=none
config -t $FLUO_APP_NAME -s table.balancer=org.apache.accumulo.server.master.balancer.RegexGroupBalancer
config -t $FLUO_APP_NAME -s table.compaction.major.ratio=1.5
config -t $FLUO_APP_NAME -s table.file.compress.blocksize.index=256K
config -t $FLUO_APP_NAME -s table.file.compress.blocksize=8K
config -t $FLUO_APP_NAME -s table.bloom.enabled=false
config -t $FLUO_APP_NAME -s table.bloom.error.rate=5%
config -s table.durability=flush
config -t accumulo.metadata -d table.durability
config -t accumulo.root -d table.durability
config -s tserver.readahead.concurrent.max=256
config -s tserver.server.threads.minimum=256
config -s tserver.scan.files.open.max=1000
EOF

# Add initial splits to the table used by Fluo Stresso Application
fluo exec $FLUO_APP_NAME stresso.trie.Split $SPLITS

echo "ACTION: Please restart Accumulo so Tablet server config will take effect"
