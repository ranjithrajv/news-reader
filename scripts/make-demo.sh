#!/usr/bin/env bash
# Turn an Omarchy screen recording into the README demo GIF.
#
#   omarchy capture screenrecording      # record, then run again to stop
#   scripts/make-demo.sh                 # newest recording -> docs/demo.gif
#   START=2 DURATION=14 scripts/make-demo.sh path/to/clip.mp4
#
# Recording itself is omarchy-capture-screenrecording's job; this only trims,
# scales and palettizes so the GIF stays small enough to load in a README.
set -euo pipefail

# shellcheck source=/dev/null
[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
VIDEOS="${XDG_VIDEOS_DIR:-$HOME/Videos}"

# shellcheck disable=SC2012  # date-stamped names, no odd characters
SRC=${1:-$(ls -t "$VIDEOS"/screenrecording-*.mp4 2>/dev/null | head -1)}
OUT=${2:-docs/demo.gif}
FPS=${FPS:-15}
WIDTH=${WIDTH:-900}
START=${START:-0}
DURATION=${DURATION:-}

[[ -f ${SRC:-} ]] || { echo "no source clip (looked in $VIDEOS); pass one as \$1" >&2; exit 1; }

trim=(-ss "$START")
[[ -n $DURATION ]] && trim+=(-t "$DURATION")

mkdir -p "$(dirname "$OUT")"
ffmpeg -y -loglevel error "${trim[@]}" -i "$SRC" \
  -vf "fps=$FPS,scale=$WIDTH:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
  -loop 0 "$OUT"

bytes=$(stat -c %s "$OUT")
printf '%s  %sB  %ss @ %sfps  %spx\n' "$OUT" "$(numfmt --to=iec --format='%.1f' "$bytes")" "${DURATION:-full}" "$FPS" "$WIDTH"
(( bytes > 10485760 )) && echo "warning: >10MB, README load will drag — lower WIDTH or DURATION" >&2
exit 0
