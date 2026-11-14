#!/bin/bash
set -euo pipefail
source_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
device="${1:-root@192.168.2.160}"
package="${2:-$source_directory/dist/musicfox-touch-luneos_0.5.0-1_aarch64.ipk}"
if [[ $# -gt 2 || ! -f "$package" ]]; then
    printf 'Usage: %s [root@device] [package.ipk]\nBuild the package first with luneos/build.sh\n' "$0" >&2
    exit 2
fi
known_hosts="${MUSICFOX_KNOWN_HOSTS:-${HOME}/.ssh/known_hosts}"
upload_directory=$(mktemp -d /tmp/musicfox-luneos-upload.XXXXXX)
trap 'rm -rf -- "$upload_directory"' EXIT
cp -- "$package" "$upload_directory/musicfox.ipk"
cp -- "$source_directory/install.py" "$source_directory/packaging/luna-call" "$upload_directory/"
remote_command=$(cat <<'REMOTE'
set -eu
temporary_directory=$(mktemp -d /tmp/musicfox-luneos-deploy.XXXXXX)
trap 'rm -rf -- "$temporary_directory"' EXIT
tar -xf - -C "$temporary_directory"
chmod 755 "$temporary_directory/luna-call"
python3 "$temporary_directory/install.py" "$temporary_directory/musicfox.ipk"
application_directory=/media/cryptofs/apps/usr/palm/applications/org.musicfox.touch
"$temporary_directory/luna-call" luna://com.webos.applicationManager/getAppInfo '{"id":"org.musicfox.touch"}'
PULSE_SERVER=unix:/run/pulse/native "$application_directory/bin/musicfox-touch" --smoke-test
"$temporary_directory/luna-call" luna://com.webos.applicationManager/launch '{"id":"org.musicfox.touch"}'
REMOTE
)
tar -C "$upload_directory" -cf - musicfox.ipk install.py luna-call | \
    ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
        -o "UserKnownHostsFile=$known_hosts" -- "$device" "$remote_command"
