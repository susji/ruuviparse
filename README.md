# ruuviparse

This program parses Ruuvi packets (RAWv2) from standard input and prints their
payload as JSON to standard output.

# How to use

Let us assume that you have a fleet of Ruuvi sensors and you would like to dump
their (valid) temperature readings as their data is somehow streamed into a MQTT
broker. Further, let us assume that

- there is a MQTT broker running at `mqtt.example.com`
- some kind of Ruuvi sensor data is being published in topic `ruuvi/001`
- you have a CA certificate, client certificate, and client private key
- you can dig out the BLE Advertising Payloads with `jq` from an array called
  `ads`...
  - which contains zero or more objects each containing hex-encoded Advertising
    Data in `ad` like this, and
  - the manufacturer-specific data is as described in [the Ruuvi
    documentation](https://docs.ruuvi.com/communication/bluetooth-advertisements).

Your data shape would be something like this:

```json
{
  "ads": [
    {
      "mac": "001122334455",
      "ad": "0201061bff990405..."
    },
    {
      "mac": "AABBCCDDEEFF",
      "ad": "0201061bff990405..."
    }
  ]
}
```

The Ruuvi RAWv2 Payload begins at `05` above, so from 7th octet which is index
14 in the hex-encoded string. To parse and pretty-print the temperature values,
you can do something like this:

```
$ mosquitto_sub \
      -h mqtt.example.com \
      -t ruuvi/001 \
      --cert ruuvi-listener.cert.pem \
      --key ruuvi-listener.private.key \
      --cafile ca.crt \
      -i ruuvi-listener \
      | jq --raw-output --unbuffered \
            '.ads[].ad | ascii_downcase | select(.[8:14] == "ff9904") | .[14:]' \
      | ruuviparse \
      | jq --raw-output --compact-output \
            'select(.Temperature.Valid) | [.Timestamp, .MAC, .Temperature.Value] | @tsv'
```
