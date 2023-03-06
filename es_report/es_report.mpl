index_stats = !elasticsearch get-index-stats --metrics "store"
node_stats = !elasticsearch get-node-stats --metrics "os,fs"

msg = "ElasticSearch usage report:\n"
msg = msg + "Number of indexes: " + len(index_stats.indices) + "\n"
msg = msg + "Node usage:\n"
for n in node_stats.nodes:
    node = node_stats.nodes[n]
    msg = msg + node.name + ":\n"
    msg = msg + "\t cpu: " + node.os.cpu.percent + "%\n"
    msg = msg + "\t memory: " + node.os.mem.used + "/" + node.os.mem.total + " used (" + node.os.mem.used_percent + "%)\n"
    msg = msg + "\t disk: " + node.fs.total.free + "/" + node.fs.total.total +" free\n"

!slack send-message --name "#general" --message msg

large_indices = json index_stats.indices[*][? .total.store.total_data_set_size_in_bytes > 30].json{"val": @0 + ": " + index_stats.indices[@0].total.store.total_data_set_size}[].val

if len(large_indices) > 0:
    msg = "These elasticsearch indices are larger than 30GB: \n"+"\n".join(large_indices)
    !slack send-message --name "#general" --message msg
