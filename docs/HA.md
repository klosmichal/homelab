# Home Assistant

What is configured in Home Assistant, why, and how to look into it when
something misbehaves. Keep this file in step with `config/homeassistant/`: any
change to a package, an integration or a device that automations depend on is
described here in the same commit.

## Moving parts

| Piece | Where it runs | Role |
|---|---|---|
| Home Assistant | `homeassistant` container, host network | Automations, UI, recorder (`home-assistant_v2.db`, SQLite) |
| Zigbee2MQTT | `zigbee2mqtt` container | Zigbee devices, published to MQTT |
| Mosquitto | `mosquitto` container, `127.0.0.1:1883` | MQTT broker between Zigbee2MQTT and HA |
| matter-server (matter.js) | `matter-server` container, host network, `127.0.0.1:5580` | Matter controller; HA's Matter integration talks to it over WebSocket |
| SLZB-MR5U | LAN device | Zigbee coordinator and Thread border router (OTBR runs on the device) |

Network details (Thread route, UFW, conntrack) are in `CLAUDE.md` under
"Zigbee, Thread and Matter".

## Where the configuration lives

| File | Owner | Sync direction |
|---|---|---|
| `config/homeassistant/configuration.yaml` | repo | push and pull |
| `config/homeassistant/packages/*.yaml` | repo | push and pull |
| `config/homeassistant/dashboards/*.yaml` | repo | push and pull |
| `config/homeassistant/www/dom/*` (floor plan drawings) | checkout, gitignored | push and pull |
| `automations.yaml`, `scenes.yaml`, `scripts.yaml` | HA UI | pull only, never pushed |
| everything under `.storage/` (integrations, devices, UI-built dashboards) | HA UI | not in the repo |

Anything that should be version-controlled goes into a package. Packages cannot
be edited from the HA UI; that is the price of having them in git. The three
UI-owned files are currently empty: every automation and scene lives in a
package.

### Deploying a package change

1. Edit the package in the repo, commit, push.
2. On the server: `cd ~/homelab && git pull`.
3. `just sync-config`. It diffs first and asks before copying. It needs sudo
   for the root-owned `AdGuardHome.yaml`, so run it in an interactive shell.
   Without sudo, copying just the changed package from the checkout to
   `/srv/homelab/homeassistant/config/packages/` is the same operation.
4. Validate, then restart:
   ```bash
   docker exec homeassistant python -m homeassistant --script check_config -c /config
   docker restart homeassistant
   ```
   `sync-config` also restarts AdGuard, Samba, qBittorrent and others; for an
   HA-only change, restarting just `homeassistant` is enough.

A restart resets every entity's `last_changed`, which delays the frozen-sensor
detection below by up to 2 h.

## Integrations

Matter, Thread, Open Thread Border Router, MQTT (Zigbee2MQTT), SMLIGHT
(SLZB-MR5U), Gree Cloud (AC, HACS), Dreame Vacuum (HACS), Google Cast (LG TV),
UPnP (Archer BE230 router), Mobile App (two iPhones), Met.no weather, Google
Translate TTS, Radio Browser, Shopping list, Bluetooth.

HACS frontend: Mushroom cards, Xiaomi Vacuum Map card, and for the "Dom"
dashboard Bubble Card (3.2 or newer) and mini-graph-card.

## Devices

| Area | Device | Model | Via | Notes |
|---|---|---|---|---|
| Salon | Czujnik salon | IKEA ALPSTUGA air quality monitor | Matter/Thread | Room temperature for the TRV; see the known issue below |
| Salon | Termostat salon | SONOFF TRVZB | Zigbee | Regulates on the external (room) temperature |
| Salon | Żyrandol salon | Philips Hue white ambiance E27 | Zigbee | |
| Salon | Kinkiet salon | Philips Hue white and colour ambiance | Zigbee | |
| Salon | Klima | Gree AC | Gree Cloud | Reports whole degrees only |
| Sypialnia | Czujnik sypialnia | IKEA TIMMERFLOTTE temp/humidity | Matter/Thread | Battery; drops off Thread often |
| Biuro | Czujnik biuro | IKEA TIMMERFLOTTE temp/humidity | Matter/Thread | Battery |
| Biuro | X50 Ultra Complete | Dreame vacuum | Dreame (HACS) | |
| none | Lampka biurowa | Philips Hue white and colour ambiance | Zigbee | |
| none | Gniazdko #1 | IKEA GRILLPLATS plug | Matter/Thread | |

Push notifications go to `notify.mobile_app_iphone_michal`.
`notify.mobile_app_iphone_natalia` also exists but nothing uses it yet.

## Salon heating — `packages/salon.yaml`

### Why the TRV uses an external sensor

The TRVZB sits on the radiator, so its built-in sensor measures the pipe as
much as the room: it reads high, and by more the hotter the radiator is. A
fixed calibration cannot fix that. Instead the valve is set to
`temperature_sensor_select: external`, and HA feeds it the ALPSTUGA's reading
through `number.termostat_salon_external_temperature_input`. With `external`
selected, the setpoint of `climate.termostat_salon` is a real room
temperature.

Zigbee2MQTT does not synchronise the external input by itself, so an
automation does it. The valve runs on batteries, so writes are throttled: one
on every 0.1 °C change, plus a heartbeat every 30 min and at HA start.

### Normal operation and fallback

```
normal      valve on `external`, fed the ALPSTUGA reading, setpoint 21 °C
   │  ALPSTUGA unavailable for 1 h, or frozen for 2 h
   ▼
fallback    calibration −3.8 °C, valve on `internal`, setpoint 21 °C,
            persistent notification + time-sensitive push
   │  readings available and changing again
   ▼
restore     fresh reading pushed, calibration 0, valve on `external`,
            setpoint 21 °C, notification dismissed + push
```

**Frozen** is `binary_sensor.salon_czujnik_zamrozony` (friendly name "Salon
czujnik nieaktywny"). It turns `on` when none of temperature, humidity and CO₂
has changed for 2 h. Over eight days of normal history the longest stretch
without a change was 62 min. Unavailable readings are ignored by this sensor:
that case has its own trigger. While it is `on`, the feed automation stops
forwarding the frozen value.

The fallback only acts when the valve is on `external`, so an outage that hits
both triggers is handled, and notified, once.

### The fallback calibration

The built-in sensor's error depends on how hot the radiator is:

| Radiator | Built-in reads above the room | Source |
|---|---|---|
| Warm, regulating normally | +3.9 °C median, +3.0…+4.6 for 90 % of the time, max +5.0 | 249 samples, 2026-11-03…04, valve on `internal` |
| Hot | up to +6.1 °C | earlier measurement |
| Mostly closed | about +1.8 °C | fallback night 2026-11-13…14: valve held 21 °C on the corrected reading while the room was at about 23 °C |

A fixed −3.8 °C correction is therefore right only at a warm radiator. With a
cold radiator the room ends up about 2 °C above the setpoint; with a very hot
one about 2 °C below. That is good enough for a fallback that lasts until the
sensor is power cycled. A second room sensor away from the radiator would be
the real improvement.

The calibration is applied only in the fallback and reset to 0 on restore.

### Scenes

All set real room temperatures, so they assume the valve is on `external`.

| Scene | Lights | TRV |
|---|---|---|
| Salon - dzień | chandelier 100 %, 4000 K; wall light off | 21 °C |
| Salon - wieczór | chandelier 55 %, 2700 K; wall light 71 %, 2400 K | 21 °C |
| Salon - film | chandelier off; wall light 24 %, 2200 K | 21 °C |
| Salon - noc | both off | 20 °C |
| Salon - wyjazd | both off, AC off | 18 °C |

The room loses only about 0.04 °C/h with the heating off, so deep setbacks
are never reached within a night. Lowering the baseline is what saves energy.

## Weekly update digest — `packages/updates.yaml`

Sundays at 10:00, if any `update.*` entity is `on`, a push lists each one as
`name: installed -> latest`; tapping it opens Settings → Updates. Covered:
Matter firmware (matter-server checks the CSA DCL), Zigbee OTA through
Zigbee2MQTT, the SLZB-MR5U, and HACS.

Nothing installs automatically. Device firmware can change how a device
behaves, and the salon regulation depends on the TRVZB's exact properties. An
OTA also costs battery devices a noticeable share of their charge. Docker
images, including HA and matter-server themselves, go through `just update`.

## "Dom" dashboard — `dashboards/dom.yaml`

A YAML-mode dashboard at `/dashboard-dom`, registered under
`lovelace: dashboards:` in `configuration.yaml`. The default dashboard, the
UI-built "Domson" and "Map" dashboards and the frontend resources stay in
storage mode, so HACS still registers its cards by itself. Because the file is
repo-owned, the dashboard cannot be edited from the HA UI.

A change to `dom.yaml` or an image needs only a browser refresh after the
copy. Registering a new dashboard, or changing `packages/dashboard.yaml`,
needs an HA restart.

| View | Contents |
|---|---|
| Dom | Badges (weather, Salon air quality, problems and pending updates when there are any), the floor plan (landscape and full width on wide screens, portrait on phones), the Salon scenes, heating, Klima and vacuum shortcuts |
| Odkurzacz | Map with room, zone and spot cleaning, start/pause/dock, cleaning mode and suction, station status, consumables |
| System | Current problems, pending updates with a link to Settings → Updates, Zigbee2MQTT / SLZB / router status, batteries |

Rooms are Bubble Card pop-ups on the Dom view (`#salon`, `#biuro`,
`#sypialnia`), opened from the floor plan or the bottom bar.
Each holds the room's thermostat, lights, scenes and 24 h sensor graphs.

**Thermostats for Biuro and Sypialnia** are already wired in as
`climate.termostat_biuro` and `climate.termostat_sypialnia`, inside
conditional cards that stay hidden while the entity does not exist. Name the
new TRVs "Termostat biuro" and "Termostat sypialnia" in Zigbee2MQTT and the
cards appear. Add each new thermostat to the `kluczowe` list in
`packages/dashboard.yaml` as well.

**Images** live in `config/homeassistant/www/dom/` and are served as
`/local/dom/…`.

- `plan-landscape.svg` and `plan-portrait.svg` are the same hand-drawn plan,
  the second rotated a quarter turn clockwise. Wide screens (900 px and up)
  get the landscape one, phones the portrait one. Elements are positioned in
  percent of the image, once per orientation, so a changed drawing means
  re-positioning them in `dom.yaml`.

The whole directory is **gitignored** because the repo is public: the
apartment plan is not committed. The files exist only on the dev
machine and on the server, so keep a copy. Put them into the server's
checkout by hand, then run `just sync-config` as usual:

```bash
ssh homelab 'mkdir -p ~/homelab/config/homeassistant/www/dom'
scp config/homeassistant/www/dom/* homelab:homelab/config/homeassistant/www/dom/
```

Where the plan puts devices that the drawing does not show: the chandelier
over the coffee table, the wall light on the wall above the sofa, Klima in
the corridor between Salon and Sypialnia, the Salon thermostat on the
radiator between the windows, the desk lamp on the left desk, the vacuum in
the built-in next to the bathroom.

**Helper sensors** — `packages/dashboard.yaml`, re-evaluated every minute:

- `sensor.dom_problemy` counts current problems and lists them in its `lista`
  attribute: a frozen Salon sensor, the TRV in fallback, Zigbee2MQTT
  disconnected, a key device unavailable, a battery under 20 % (phones and the
  vacuum excluded).
- `sensor.dom_aktualizacje` counts `update.*` entities that are `on`.

HA's persistent notifications cannot be listed by a card, so the System view
shows the conditions behind them instead.

## Known issues

### ALPSTUGA freezes on firmware 1.0.26

On 2026-11-11 at 04:50 the ALPSTUGA froze every reading (temperature 23.9 °C,
CO₂ 501 ppm) while staying available. Its Matter subscription stayed healthy,
it answered keep-alives, and a direct attribute read returned the frozen
value. Its hourly time-sync events stopped at the same moment. Only a power
cycle (USB-C) brings it back. Other users report the same on 1.0.26, and 1.0.26
is the newest firmware on the DCL.

This incident is why the frozen-sensor detection exists. It first fired on
2026-11-13 at 18:38; the sensor was power cycled and control returned on
2026-11-14 at 04:00.

### ALPSTUGA has no time

matter-server logs `timeSynchronization.timeFailure` from node 1 every hour.
The device never gets a valid time from the controller. Not known to be related
to the freeze.

## Troubleshooting

All from the dev machine through `ssh homelab`. HA has no API token on the
server, so the recorder database and matter-server's WebSocket are the way in.
The HA container has Python, `sqlite3` and `aiohttp`.

**History of an entity.** Pipe a script into the container, since quoting
through ssh mangles SQL strings:

```python
# history.py — run: ssh homelab 'docker exec -i homeassistant python3 -' < history.py
import sqlite3
c = sqlite3.connect("file:/config/home-assistant_v2.db?mode=ro", uri=True)
for row in c.execute("""
    select datetime(s.last_updated_ts, 'unixepoch', 'localtime'), s.state
    from states s join states_meta m on s.metadata_id = m.metadata_id
    where m.entity_id = ? order by s.last_updated_ts desc limit 20""",
    ("sensor.salon_czujnik_salon_temperature",)):
    print(row)
```

**Matter nodes and a direct read from a device:**

```python
# matter.py — run the same way
import asyncio, aiohttp
async def main():
    async with aiohttp.ClientSession() as s:
        async with s.ws_connect("http://127.0.0.1:5580/ws") as ws:
            await ws.receive_json()  # server info
            await ws.send_json({"message_id": "r", "command": "read_attribute",
                                "args": {"node_id": 1, "attribute_path": "1/1026/0"}})
            while (m := await ws.receive_json()).get("message_id") != "r":
                pass
            print(m)  # 1/1026/0 is temperature in 0.01 °C
asyncio.run(main())
```

Use `{"command": "get_nodes"}` for every node with availability and cached
attributes. Node 1 is the ALPSTUGA, 2 and 3 the TIMMERFLOTTEs, 4 the
GRILLPLATS plug.

**matter-server logs** (strip colour codes first):

```bash
ssh homelab 'docker logs --since 24h matter-server 2>&1 | sed "s/\x1b\[[0-9;]*m//g" | grep "@1:1"'
```

**Zigbee2MQTT device definitions**, for value ranges such as the TRV's
calibration limits (−12.7…12.7 °C in 0.2 °C steps):

```bash
ssh homelab 'cd ~/homelab && set -a && . ./.env && set +a && docker exec mosquitto mosquitto_sub -h 127.0.0.1 -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -t zigbee2mqtt/bridge/devices -C 1 -W 10'
```
