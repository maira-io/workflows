cpu_threshold = 0.2
net_in_threshold = 5 * 1024 * 1024
net_out_threshold = 5 * 1024 * 1024

def max(l):
    m = 0
    for item in l:
        if item > m:
            m = item
    return m

instances = !ec2 list-instances
ids = instances.instances[].instance_id
idle_instances = json []

for id in ids:
    dim = json {"InstanceId": id}
    cpu = !cloudwatch get-metric-stats "CPUUtilization" --dimensions dim --stat "Average" --period 3600  --namespace "AWS/EC2" --start_time "7 days ago" --end_time "now"
    max_cpu = max(cpu[].average)

    net_in = !cloudwatch get-metric-stats "NetworkIn" --dimensions dim --stat "Average" --period 3600  --namespace "AWS/EC2" --start_time "7 days ago" --end_time "now"
    max_net_in = max(net_in[].average)

    net_out = !cloudwatch get-metric-stats "NetworkOut" --dimensions dim --stat "Average" --period 3600  --namespace "AWS/EC2" --start_time "7 days ago" --end_time "now"
    max_net_out = max(net_out[].average)

    if max_cpu < cpu_threshold && max_net_in < net_in_threshold && max_net_out < net_out_threshold:
        idle_instances = idle_instances + id

if len(idle_instances) > 0:
    msg = "The following EC2 instances have been idle for 7 days: " + idle_instances + ". OK to terminate them?"
    ok = !confirm msg
    if ok == "approved":
        for id in idle_instances:
            !ec2 terminate-instance id
        msg = "The following idle EC2 instances were terminated: " + idle_instances
        !slack send-message --name "#general" --message msg
    else:
        msg = "The following EC2 instances have been idle for 7 days: " + idle_instances
        !slack send-message --name "#general" --message msg
