#!/bin/sh

set -u

BROKERHOST=broker.example.com
BROKERPORT=1883
TOPIC=ruuvi/topic
CLIENTID=ruuvimetrics
AUTH='--cert cert.cert.pem --key key.private.key --cafile ca.crt'
F=metrics.txt
# Change this according to your setup.
ACT="/bin/cp $HOME/ruuvimetrics/${F} /var/www/htdocs/metrics"

# Due to fromdateiso8601.
export TZ=UTC

info() {
  printf "%s\n" "$*" 1>&2
}

val() {
  _mac="$1"
  _kind="$2"
  _ok="$3"
  _val="$4"
  _ts="$5"
  info "[$_mac] $_kind: $_val ($_ok)"
  _p="ruuvi_${_kind}"
  if [ "$_ok" = "true" ]; then
    # We have a new valid value so filter out the old one.
    _m="{mac=\"$_mac\"}"
    cat "$F" | fgrep "${_p}{mac=" | fgrep -v "$_m"
    echo "${_p}${_m} $_val $_ts"
  else
    # No new valid value so just copy all we have.
    cat "$F" | fgrep "${_p}{mac="
  fi
}

dump() {
  _kind="$1"
  _tmpf="$2"
  { echo "# TYPE ruuvi_${_kind} gauge"; cat "$_tmpf"; } | sort
}

activate() {
  $ACT
}

rm -f "$F" && touch "$F"
mosquitto_sub \
  -h "$BROKERHOST" \
  -p "$BROKERPORT" \
  -t "$TOPIC" \
  -i "$CLIENTID" \
  $AUTH \
  | jq --raw-output --unbuffered \
          '.ads[].ad | ascii_downcase | select(.[8:14] == "ff9904") | .[14:]' \
  | ruuviparse \
  | jq --raw-output --unbuffered \
    '. + { "OriginalTimestamp": .Timestamp }
     | .Timestamp |= .[:index(".")] + "Z"
     | .Timestamp |= fromdateiso8601 * 1000
     | [.OriginalTimestamp,
        .Timestamp,
        .MAC,
        .Temperature.Valid,
        .Temperature.Value,
        .BatteryVoltage.Valid,
        .BatteryVoltage.Value,
        .MovementCounter.Valid,
        .MovementCounter.Value]
     | @tsv' \
  | while read -r ots ts mac vtemp temp vvolt volt vmove move; do
    info "[$mac] $ots"
    ttemp=$(mktemp)
    tvolt=$(mktemp)
    tmove=$(mktemp)
    val "$mac" "temperature" "$vtemp" "$temp" "$ts" > "$ttemp"
    val "$mac" "voltage" "$vvolt" "$volt" "$ts" > "$tvolt"
    val "$mac" "movement" "$vmove" "$move" "$ts" > "$tmove"
    echo "# Generated at $(date) by $(basename "$0")" > "$F"
    dump "temperature" "$ttemp" >> "$F"
    dump "voltage" "$tvolt" >> "$F"
    dump "movement" "$tmove" >> "$F"
    activate
    rm -f "$ttemp" "$tvolt" "$tmove"
  done
