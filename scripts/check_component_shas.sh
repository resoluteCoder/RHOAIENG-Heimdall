#!/bin/bash
set -e

echo "Checking latest SHAs for all components..."
echo "=========================================="
echo ""

# Component data structure: "display_name|repo_url|branch|current_sha"
declare -a COMPONENTS=(
    "dashboard|opendatahub-io/odh-dashboard|main|1dfe5f6666c1d44e297eec315ba401624e6ff86a"
    "kubeflow controllers|opendatahub-io/kubeflow|main|121a467690d03514277a7d30c16c311815b1877f"
    "notebooks|opendatahub-io/notebooks|main|40a15f26ca1f3af8135ddbadee43708501cd19b1"
    "kserve|opendatahub-io/kserve|release-v0.15|1381fab8f77e7d5b211f634506a7a09e97345655"
    "ray|opendatahub-io/kuberay|dev|d751b14faddf13b141d0d26f6ced640ec23030b3"
    "trustyai|opendatahub-io/trustyai-service-operator|incubation|7f21761643ea756480f0a43f55ff8817458559a4"
    "modelregistry|opendatahub-io/model-registry-operator|main|b3a24d0cdf336dac7e584fa054147cd4c7680007"
    "trainingoperator|opendatahub-io/training-operator|dev|fc212b8db7fde82f12e801e6778961097899e88d"
    "datasciencepipelines|opendatahub-io/data-science-pipelines-operator|main|1aec8b555de9213ffb6db52ff5ec8ad84d5cf23a"
    "modelcontroller|opendatahub-io/odh-model-controller|incubating|b6f93228505d15862a3085fe03a719d0c7ea6c6a"
    "feastoperator|opendatahub-io/feast|stable|4a738d9af833f02a44ae37de5562214d366b014d"
    "llamastackoperator|opendatahub-io/llama-stack-k8s-operator|odh|c99ed0472cfd4e709e8722dcc38e0a52f0e37141"
)

# Function to get commit date using jq
get_commit_date() {
    local repo_path=$1
    local sha=$2
    curl -s "https://api.github.com/repos/${repo_path}/commits/${sha}" | jq -r '.commit.committer.date // empty'
}

# Function to format relative time
get_relative_time() {
    local commit_date=$1
    if [ -z "$commit_date" ] || [ "$commit_date" == "null" ]; then
        echo "unknown"
        return
    fi
    local commit_timestamp=$(date -d "$commit_date" +%s 2>/dev/null || echo "0")
    if [ "$commit_timestamp" == "0" ]; then
        echo "unknown"
        return
    fi
    local now=$(date +%s)
    local diff=$((now - commit_timestamp))
    local days=$((diff / 86400))
    local weeks=$((days / 7))
    local months=$((days / 30))

    if [ $days -eq 0 ]; then
        echo "today"
    elif [ $days -eq 1 ]; then
        echo "1 day ago"
    elif [ $weeks -eq 0 ]; then
        echo "$days days ago"
    elif [ $weeks -eq 1 ]; then
        echo "1 week ago"
    elif [ $months -eq 0 ]; then
        echo "$weeks weeks ago"
    elif [ $months -eq 1 ]; then
        echo "1 month ago"
    else
        echo "$months months ago"
    fi
}

# Function to check a single component
check_component() {
    local index=$1
    local display_name=$2
    local repo_path=$3
    local branch=$4
    local current_sha=$5

    echo "${index}. ${display_name} (${repo_path}:${branch})"

    # Get latest SHA
    local latest_sha=$(git ls-remote "https://github.com/${repo_path}.git" "${branch}" | head -1 | awk '{print $1}')

    # Get current commit date
    local current_date=$(get_commit_date "${repo_path}" "$current_sha")
    local current_relative=$(get_relative_time "$current_date")
    echo "   Current: $current_sha ($current_relative)"

    # Check if outdated
    if [ "$latest_sha" != "$current_sha" ]; then
        local latest_date=$(get_commit_date "${repo_path}" "$latest_sha")
        local latest_relative=$(get_relative_time "$latest_date")
        echo "   Latest:  $latest_sha ($latest_relative)"
        echo "   ⚠️  OUTDATED"
    else
        echo "   ✓ Up to date"
    fi
    echo ""
}

# Main loop - iterate over all components
index=1
for component in "${COMPONENTS[@]}"; do
    # Split the component string by pipe delimiter
    IFS='|' read -r display_name repo_path branch current_sha <<< "$component"

    # Check this component
    check_component "$index" "$display_name" "$repo_path" "$branch" "$current_sha"

    ((index++))
done
