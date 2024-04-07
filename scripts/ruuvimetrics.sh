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

val() {
  _mac="$1"
  _kind="$2"
  _ok="$3"
  _val="$4"
  _tmpf="$5"
  echo "[$_mac] $_kind: $_val ($_ok)"
  _p="ruuvi_${_kind}"
  if [ "$_ok" = "true" ]; then
    # We have a new valid value so filter out the old one.
    _m="{mac=\"$_mac\"}"
    cat "$F" | fgrep "${_p}{mac=" | fgrep -v "$_m"  > "$_tmpf"
    echo "${_p}${_m} $_val $_ts" >> "$_tmpf"
  else
    # No new valid value so just copy all we have.
    cat "$F" | fgrep "${_p}{mac=" > "$_tmpf"
  fi
}

dump() {
  _kind="$1"
  _tmpf="$2"
  { echo "# TYPE ruuvi_${_kind} gauge"; cat "$_tmpf"; } | sort >> "$F"
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
     | . + {"CompareTimestamp": (.Timestamp / 1000 | todate) }
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
  | while read -r _ots _ts _mac _vtemp _temp _vvolt _volt _vmove _move; do
    echo "[$_mac] $_ots"
    _ttemp=$(mktemp)
    _tvolt=$(mktemp)
    _tmove=$(mktemp)
    val "$_mac" "temperature" "$_vtemp" "$_temp" "$_ttemp"
    val "$_mac" "voltage" "$_vvolt" "$_volt" "$_tvolt"
    val "$_mac" "movement" "$_vmove" "$_move" "$_tmove"
    rm -f "$F"
    echo "# Generated at $(date) by $(basename "$0")" > "$F"
    dump "temperature" "$_ttemp"
    dump "voltage" "$_tvolt"
    dump "movement" "$_tmove"
    activate
    rm -f "$_ttemp" "$_tvolt" "$_tmove"
  done
