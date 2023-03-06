# Crash Monitor

This is a simple workflow that can monitor logs for any kubernetes pods. When a new crash is detected, the workflow first extracts the traceback lines from logs, and uses it to identify if it is a new crash or seen previously. To do this, it first removes variable information from the traceback and finds an MD5 hash of the traceback. Then it searches GitHub for previously filed issues with that traceback. If one is found, it will add a comment in that issue, otherwise it will create a new issue with the traceback and MD5 and other necessary details

This workflow uses a Maira built-in command called `find stacktrace` that can be used to find stack traces in log files for many different languages. Many common languages such as Go, C, C++, java, python, ruby, javascript are supported and more will be added in future. 


## Alternative implementations

This workflow uses GitHub for issue management, but if you use other issue tracking system, you can easily replace the corresponding commands. Maira supports GitLab, BitBucket, Jira and you can add custom support for issue tracker you use if it is not already supported.




