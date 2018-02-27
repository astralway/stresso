/*
 * Copyright 2014 Stresso authors (see AUTHORS)
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License. You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed under the License
 * is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
 * or implied. See the License for the specific language governing permissions and limitations under
 * the License.
 */

package stresso.trie;

import java.util.TreeSet;

import javax.inject.Inject;

import com.google.common.base.Strings;
import org.apache.accumulo.core.client.Connector;
import org.apache.fluo.api.client.FluoClient;
import org.apache.fluo.api.client.FluoFactory;
import org.apache.fluo.api.config.FluoConfiguration;
import org.apache.fluo.core.util.AccumuloUtil;
import org.apache.hadoop.io.Text;

public class Split {

  @Inject
  private static FluoConfiguration config;

  public static void main(String[] args) throws Exception {
    if (args.length != 1) {
      System.err.println("Usage: " + Split.class.getSimpleName()
          + " <tablets per level>");
      System.exit(-1);
    }

    int maxTablets = Integer.parseInt(args[0]);

    int nodeSize;
    int stopLevel;
    try (FluoClient client = FluoFactory.newClient(config)) {
      nodeSize = client.getAppConfiguration().getInt(Constants.NODE_SIZE_PROP);
      stopLevel = client.getAppConfiguration().getInt(Constants.STOP_LEVEL_PROP);
    }

    int level = 64 / nodeSize;

    while (level >= stopLevel) {
      int numTablets = maxTablets;
      if (numTablets == 0)
        break;

      TreeSet<Text> splits = genSplits(level, numTablets);
      addSplits(config, splits);
      System.out.printf("Added %d tablets for level %d\n", numTablets, level);

      level--;
    }
  }

  private static TreeSet<Text> genSplits(int level, int numTablets) {

    TreeSet<Text> splits = new TreeSet<>();

    String ls = String.format("%02d:", level);

    int numSplits = numTablets - 1;
    int distance = (((int) Math.pow(Character.MAX_RADIX, Node.HASH_LEN) - 1) / numTablets) + 1;
    int split = distance;
    for (int i = 0; i < numSplits; i++) {
      splits.add(new Text(
          ls + Strings.padStart(Integer.toString(split, Character.MAX_RADIX), Node.HASH_LEN, '0')));
      split += distance;
    }

    splits.add(new Text(ls + "~"));

    return splits;
  }

  private static void addSplits(FluoConfiguration config, TreeSet<Text> splits) throws Exception {
    Connector conn = AccumuloUtil.getConnector(config);
    conn.tableOperations().addSplits(config.getAccumuloTable(), splits);
  }
}
