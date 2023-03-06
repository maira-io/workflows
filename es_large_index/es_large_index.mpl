stats = ! elasticsearch get-index-stats "_all" --metrics "store"
large_indices = json []

# @label: Go over all indices
for index in stats.indices: 
    # @label: index size > 1000000?
    if stats.indices[index].total.store.total_data_set_size_in_bytes > 10000:
        item = index + ": " + stats.indices[index].total.store.total_data_set_size
        large_indices.append(item)

# @label: Any large index found?
if len(large_indices) > 0:
    msg = "These elasticsearch indices are larger than 1MB: \n"+"\n".join(large_indices)
    ! slack send-message --name "#general" --message msg

