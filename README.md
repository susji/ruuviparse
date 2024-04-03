# ruuviparse

This program parses Ruuvi packets (RAWv2) from standard input and prints their
payload as JSON to standard output.

# Installing

Get a ready [release](https://github.com/susji/ruuviparse/releases) or use the
Go toolchain like this:

    $ go install github.com/susji/ruuviparse@latest

# Simple example

We can feed Ruuvi's [test
vectors](https://docs.ruuvi.com/communication/bluetooth-advertisements/data-format-5-rawv2#test-vectors)
to `ruuviparse`:

    $ echo '0512FC5394C37C0004FFFC040CAC364200CDCBB8334C884F' | ruuviparse | jq

<details>
    <summary>View output</summary>

```json
{
  "Type": 5,
  "Timestamp": "2024-04-04T00:20:22.201683+03:00",
  "Temperature": {
    "Valid": true,
    "Value": 24.3
  },
  "Humidity": {
    "Valid": true,
    "Value": 53.489998
  },
  "Pressure": {
    "Valid": true,
    "Value": 100044
  },
  "AccelerationX": {
    "Valid": true,
    "Value": 4
  },
  "AccelerationY": {
    "Valid": true,
    "Value": -4
  },
  "AccelerationZ": {
    "Valid": true,
    "Value": 1036
  },
  "BatteryVoltage": {
    "Valid": true,
    "Value": 2.977
  },
  "TransmitPower": {
    "Valid": true,
    "Value": 4
  },
  "MovementCounter": {
    "Valid": true,
    "Value": 66
  },
  "SequenceNumber": {
    "Valid": true,
    "Value": 205
  },
  "MAC": "cb:b8:33:4c:88:4f"
}
```

</details>

# Integrating with MQTT messaging

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
- you have a suitable MQTT client installed
  - the example below uses `mosquitto_sub`

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
14 in the hex-encoded string. We can also pick Ruuvi messages by filtering with
`ff9904` which means manufacturer-specific data and Ruuvi's unique identifier.
To parse and pretty-print the temperature values, you can do something like
this:

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

For an example how to insert the data into a database, see the documentation for
[ruuviscan](https://github.com/susji/ruuviscan?tab=readme-ov-file#storing-temperature-values-in-an-sqlite-database).
