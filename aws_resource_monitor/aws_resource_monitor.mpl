#
# Constants
#

# @label: Resource state definitions
state = json {
	"inuse":    "in-use",
	"notinuse": "not-in-use",
	"notified": "notified",
	"expired":  "expired",
	"deleted":  "deleted"
}

# @label: Default values for lease options
options = json {
	"lease_period":	3,
	"lease_notify_period": 2
}

#
# Global variables
#

# Now
time_now = time now

# Resources discovered
res_list = json []

# Resources already in the DB
res_list_in_db = json []

# List of users to notified { "user": [ res1, res2 ] }
notify_list = json {}

# @label: Initialize options
def init_options():
	if input.options == null:
		return

	# @label: Lease period specified?
	if input.options.lease_period_default:
		options.lease_period = input.options.lease_period_default

	# @label: Notify period specified?
	if input.options.lease_notify_period:
		options.lease_notify_period = input.options.lease_notify_period

# @label: Get owner from tags
def get_owner_from_tags(tags):
	# AWS resource tags indicating the current owner
	owner_tag = input.owner_tag.string()
	return tags.get(owner_tag, "")

def get_tags_arg():
	tags_arg = json[]
	if input.filters:
		tags_arg = input.filters

	if input.owners:
		owner_tag = input.owner_tag + " = [" + ",".join(input.owners) + "]"
		tags_arg.append(owner_tag)
	return tags_arg

# @label: Get the list of resources from the DB for this resource monitor
def get_list_from_db():
	resp = !maira list-resources -namespace input.namespace -resource_monitor input.name
	if resp && resp.resources:
		resources = resp.resources
	else:
		resources = json []
	return resources

# @label: Update the resources in DB
def update_in_db():
	if len(res_list) == 0:
		return null

	resp = !maira update-resources -namespace input.namespace -resource_monitor input.name res_list
	return resp

# @label: Add a log to the resource event log
def add_log(res, msg):
	evtLog = json { "time": time_now.string("RFC3339"), "message": msg, "resource_monitor": input.name }
	res.events = res.events + evtLog

# @label: Set lease info for the resource
def set_lease_info(res, res_state, expiry, msg):
	res.resource_monitors[input.name].state = res_state

	if expiry != "":
		res.resource_monitors[input.name].expiry = expiry

	if msg != "":
		add_log(res, msg)

# @label: Delete a resource
def res_delete(res):
	id = res.identifier
	if id.object_type == "instance":
		x = !ec2 terminate-instance -site res.site id.object_id
	if id.object_type == "volume":
		x = !ec2 delete-volume -site res.site id.object_id
	set_lease_info(res, state.deleted, "Deleted by Maira", "Deleted")

# @label: Find instances
def find_instances(sites, tags_arg):
	res_inst_list = json []

	for site in sites:
		il = !ec2 list-instances -site site -tags tags_arg

		if il == null:
			continue

		instances = il.get("instances")
		if instances == null:
			continue
		
		inst_list = json instances[? .state != "TERMINATED"]
		ri_list = inst_list[].json {
			"identifier": {
				"service_type": "ec2",
				"service_instance": "default",
				"namespace": "default",
				"object_type": "instance",
				"object_id": .instance_id
			},
			"zone": .availability_zone,
			"labels": .tags,
			"owner": get_owner_from_tags(.tags),
			"resource_monitors": { input.name: {"state": state.inuse}},
			"events": [],
			"namespace": input.namespace,
			"site": site
		}
		res_inst_list = res_inst_list + ri_list

	return res_inst_list

# @label: Find EBS volumes
def find_volumes(sites, tags_arg):
	res_vol_list = json []

	for site in sites:
		vl = !ec2 list-volumes -site site -tags tags_arg

		if vl == null:
			continue

		volumes = vl.get("volumes")
		if volumes == null:
			continue

		vol_list = json volumes[? .state != "deleting" && .state != "deleted" ]

		rv_list = vol_list[].json {
			"identifier": {
				"service_type": "ec2",
				"service_instance": "default",
				"namespace": "default",
				"object_type": "volume",
				"object_id": .volume_id
			},
			"zone": .availability_zone,
			"labels": .tags,
			"owner": get_owner_from_tags(.tags),
			"resource_monitors": { input.name: {"state": state.inuse}},
			"events": [],
			"namespace": input.namespace,
			"site": site
		}
		res_vol_list = res_vol_list + rv_list

	return res_vol_list

# @label: Sync up the resources found to those already in DB
def sync_with_in_db():
	res_deleted = json []

	# @label: Look for any resources that got deleted
	for res_in_db in res_list_in_db:

		# skip resources marked as deleted/notinuse in db
		lease_info = res_in_db.resource_monitors[input.name]
		if lease_info.state == state.deleted || lease_info.state == state.notinuse:
			continue

		res = res_list[? .identifier == res_in_db.identifier]
		if res:
			# @label: Resource is still inuse
			res.resource_monitors[input.name] = lease_info
			res.desired_expiry = res_in_db.desired_expiry
		else:
			# @label: Resource in DB is deleted now, it needs to be updated
			res = res_in_db
			res.resource_monitors = json {input.name: {"state": state.notinuse, "expiry": lease_info.expiry}}
			res.events = json []
			add_log(res, "Not in use or deleted")
			res_deleted = res_deleted + res

	# @label: Look for any resources that got added after the last run
	for res in res_list:
		res_in_db = res_list_in_db[? .identifier == res.identifier]
		if res_in_db:
			# @label: Resource is already in the DB
			lease_info = res_in_db.resource_monitors[input.name]

			# add a log, if this resource was previously notinuse state
			if lease_info.state == state.notinuse:
				add_log(res, "Rediscovered")
		else:
			# @label: A new resource is discovered now
			add_log(res, "Discovered")

	# add deleted resource also
	res_list = res_list + res_deleted

	return res_list

# @label: Initialize lease info
def lease_init(res):
	lease_period = options.lease_period * 24

	x = time_now + lease_period.duration("hr")
	expiry = x.string("RFC3339")
	msg = "Lease initialized and set till " + expiry
	set_lease_info(res, state.inuse, expiry, msg)

# @label: Get lease expiry
def lease_get_expiry(res):
	# if desired_expiry is set, use that
	if res.desired_expiry:
		expiry = res.desired_expiry.time()
		res.resource_monitors[input.name].expiry = expiry
	else:
		lease_info = res.resource_monitors[input.name]
		expiry = lease_info.expiry.time()
	return expiry

# @label: Mark the lease as expired
def lease_expired(res):
	# @label: Mark the resource as lease expired
	set_lease_info(res, state.expired, "", "Lease expired")

	# @label: Delete the resource
	#res_delete(res)

# @label: Set lease expiry notification for a resource
def lease_set_notify_expiry(res):
	owner = res["owner"]
	if owner == null:
		set_lease_info(res, state.notified, "", "No owner to notify")
		return

	msg = "Lease expiring soon; notifying owner " + owner
	set_lease_info(res, state.notified, "", msg)

	id = res.identifier
	lease_info = res.resource_monitors[input.name]

	rn = json {
		"identifier": "AWS EC2 " + id.object_type + " " + id.object_id,
		"lease_expiry_time": lease_info.expiry
	}

	if owner in notify_list:
		notify_list[owner].append(rn)
	else:
		notify_list[owner] = json [ rn ]

# @label: Notify lease expiry to the owners of the resources
def lease_notify_expiry():
	for owner in notify_list:
		en = owner.split("@")
		url = "https://demo.maira.io/resource/" + input.name
		res_list = notify_list[owner]

		email_args = json {
			"name": en[0],
			"url":  url,
			"resources": res_list
		}

		# Send a notification email
		!send-email -to owner -template "d-e776947b70ca4d78a66e736ce3ec75ed" email_args
	return

# @label: Lease Monitor for the resources
def lease_monitor():
	# Lease notify time in hours
	lease_notify_period = options.lease_notify_period * 24

	# @label: Iterate thru the resources for monitoring the lease
	for res in res_list:
		lease_info = res.resource_monitors[input.name]
		# @label: Resource deleted or not in use?
		if lease_info.state == state.deleted || lease_info.state == state.notinuse:
			continue

		# @label: No lease expiry set?
		if lease_info.expiry == null:

			# @label: No lease expiry set for the resource, initialize lease info
			lease_init(res)
		else:
			# @label: Check for lease expiry for the resource
			expiry = lease_get_expiry(res)
			if expiry < time_now:
				# @label: Lease is expired for this resource
				lease_expired(res)
			else:
				# @label: Lease is not expired for this resource
				remain = expiry - time_now
				# @label: Lease about to expire and not notified?
				if remain.hours() <= lease_notify_period && lease_info.state != state.notified:
					# @label: Lease is about to expire; notify the owner
					lease_set_notify_expiry(res)

	# @label: Notify any pending lease expiries
	lease_notify_expiry()

# @label: Initialize lease options
init_options()

# @label: Get the list of sites
sites = !maira list-sites -namespace input.namespace

# @label: Get the resources in db
res_list_in_db = get_list_from_db()

# @label: Get tags arguments (from filters/owner)
tags_arg = get_tags_arg()

# @label: Find resources
res_list = find_instances(sites, tags_arg) + find_volumes(sites, tags_arg)

# @label: Sync up the resources found to those already in the DB
res_list = sync_with_in_db()

# @label: Lease monitor
lease_monitor()

print res_list

# @label: Update resources in the DB
update_in_db()
