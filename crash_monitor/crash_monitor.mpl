site = "maira-site-1"
namespace = "maira"

logs = !k8s get-pod-logs --site site --namespace namespace --label_selector "app.kubernetes.io/name=r1-api" --since "2h"
traces = !find stacktrace logs.logs

for st in traces:
    md5 = "[hash=" + st.isum +"]"
    issues = !github search-issues --site site --repo "maira-io/apiserver" md5
    lines = json st.frames[].line
    lines = "```" + "\n".join(lines) + "```"

    # @label: No existing issue?
    if issues.total_count == 0:
        body = md5 + "\n\nStacktrace\n" + lines
        !github create-issue --site site --repo "maira-io/apiserver" --title "Stacktrace found by maira" --body body --label "maira"
    else:
        !github add-issue-comment --site --repo "maira-io/apiserver --issue issues[0].items[0].number lines 
