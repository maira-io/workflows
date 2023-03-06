# ElastiSearch Usage Report

This workflow sends a periodic report of your ElasticSearch cluster. For each node, it reports CPU, memory and disk utilization and for each index, it sends list of indexes larger than specified threshold. All this data is sent in a slack message.

