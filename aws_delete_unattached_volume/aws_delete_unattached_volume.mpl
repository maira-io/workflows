vols = !ec2 list-volumes --state "available"
for vol in vols.volumes[].volume_id:
    !ec2 delete-volume vol
