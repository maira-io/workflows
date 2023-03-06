# AWS Resource Monitor

This workflow can help users in identifying unused/left behind resources in AWS. The workflow periodically scans all your AWS resources (EC2 instances and volumes are supported currently, more resources types can be supported in future). It assumes that all resources are tagged with a unique tag that can be used to identify the owner of those resources. 

Below is the sequence of steps:

* For each new found resource, it adds it to Maira database and sets a predefined _expiry_ date on it.
* Two days before the expiry, it sends a notification to the owner that their resource may be expiring. They have three choices at this time. Either they can delete the resource right away, or extend the expiry by another 3 days, or let the resource expire.
* One day before the expiry, it sends another reminder about the expiring resources.
* Any resources for which no action is taken by the user, are deleted after the expiry time.
* If the owner chooses to extend expiry, the expiry date is extended by 3 days and the owner will be contacted again 2 days before the new expiry if the resource still exists at that time


You can view the resources identified, their expiry and any action taken by the workflow using Maira UI.
