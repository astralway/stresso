package stresso.trie;

import java.io.File;

import org.apache.accumulo.core.client.Connector;
import org.apache.fluo.api.client.FluoAdmin;
import org.apache.fluo.api.client.FluoFactory;
import org.apache.fluo.api.config.FluoConfiguration;
import org.apache.fluo.core.util.AccumuloUtil;
import org.apache.hadoop.io.Text;

/**
 * Compact the lower levels of the tree. The lower levels of the tree contain a small of nodes that
 * are frequently updated. Compacting these lower levels is a quick operation that cause the Fluo GC
 * iterator to cleanup past transactions.
 */

public class CompactLL {
  public static void main(String[] args) throws Exception {

    if (args.length != 3) {
      System.err
          .println("Usage: " + Split.class.getSimpleName() + " <fluo conn props> <max> <cutoff>");
      System.exit(-1);
    }

    FluoConfiguration config = new FluoConfiguration(new File(args[0]));

    try(FluoAdmin admin = FluoFactory.newAdmin(config)) {
      // Get the application config stored in zookeeper which has Accumulo connection properties
      config = new FluoConfiguration(config.orElse(admin.getApplicationConfig()));
    }

    long max = Long.parseLong(args[1]);

    //compact levels that can contain less nodes than this
    int cutoff = Integer.parseInt(args[2]);

    int nodeSize = config.getAppConfiguration().getInt(Constants.NODE_SIZE_PROP);
    int stopLevel = config.getAppConfiguration().getInt(Constants.STOP_LEVEL_PROP);

    int level = 64 / nodeSize;

    while(level >= stopLevel) {
      if(max < cutoff) {
        break;
      }

      max = max >> 8;
      level--;
    }

    String start = String.format("%02d", stopLevel);
    String end = String.format("%02d:~", (level));

    System.out.println("Compacting "+start+" to "+end);
    Connector conn = AccumuloUtil.getConnector(config);
    conn.tableOperations().compact(config.getAccumuloTable(), new Text(start), new Text(end), true, false);

    System.exit(0);
  }
}
