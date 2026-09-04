# Jellyfin playback on the LG G4

Settings and measured compatibility for the LG OLED G4 + LG SC9S soundbar.
These were established empirically from Jellyfin's ffmpeg session logs — see the
"How to verify" section to re-derive any of it after a reinstall.

## Jellyfin app settings on the TV (webOS)

These matter more than anything on the server. Three of them caused a multi-day
playback failure when set wrongly.

| Setting | Value | Why |
|---|---|---|
| Quality | **Auto** | A fixed bitrate cap (it was pinned at 120 Mbps) forces HLS delivery instead of direct play. |
| Prefer fMP4-HLS container | **ON** | With this off the TV receives MPEG-TS, which is a poor carrier for HEVC and caused stuttering and full video re-encodes. |
| Use shorter HLS segments | **OFF** | With this on, segments are 1 second — 3000+ segment requests per film. Only useful for live low-latency. |
| Preferred audio transcoding codec | **AC3** | When a transcode is unavoidable, AC3 5.1 reaches the soundbar as real surround. AAC is the fallback default. |
| Preferred video transcoding codec | **Auto** | Choosing HEVC does nothing while the server has `AllowHevcEncoding` off. |
| DTS (DCA) | ON | Harmless, but does not produce direct play — DTS transcodes regardless. |
| TrueHD | **ON** | Required for TrueHD direct play. With it off, TrueHD is silently re-encoded to AAC. |
| VBR sound coding | leave default | Slightly better quality per bitrate on transcodes. |

## Server-side Jellyfin settings

| Setting | Value | Why |
|---|---|---|
| Hardware acceleration | QSV, `/dev/dri/renderD128` | Intel Quick Sync on the N200. |
| Intel OpenCL runtime | via `DOCKER_MODS` in `docker-compose.yml` | Jellyfin initialises an OpenCL device whenever HDR tone mapping is on. Without it every HDR transcode dies instantly with `Failed to get number of OpenCL platforms` (exit 237). |
| Tone mapping | Enabled | Needed for HDR → SDR on browser clients. |
| `AllowHevcEncoding` | Off | Clients that trigger a transcode are the ones that cannot decode HEVC, so H.264 output is correct. |
| `EnableSegmentDeletion` | **On** | Off by default; the transcode cache had grown to 7.4 GB of stale segments. |

## TV picture settings

- **Instant Game Response / ALLM** on the Jellyfin input — reduces processing lag.
- **TruMotion off** for film — 24 fps content should look like 24 fps.
- **eARC passthrough** to the SC9S so TrueHD and Atmos bypass the TV's decoder.

## Measured compatibility

Direct play means no ffmpeg session is created at all.

| | Direct-plays | Forces a re-encode |
|---|---|---|
| Video | HEVC, H.264 | Dolby Vision **P7** (`DOVIWithEL`) |
| Audio | AAC, AC3, E-AC3, TrueHD | **DTS** |
| Subtitles | SRT (text) | **PGS** (bitmap, burned in) |
| Containers | MKV, MP4 | — |

Notes:

- **DTS never direct-plays** despite the app toggle being on. Six tracks tested
  across three container configurations, with and without the soundbar.
- **PGS is the expensive one.** Selecting a PGS track on a file that otherwise
  direct-plays produces `overlay_qsv` burn-in and a full 4K re-encode.
- **Dolby Vision P7** is reported as "video range type is not supported" and is
  tone-mapped to H.264 SDR. Convert to P8.1 with `dovi_tool` (metadata-only).
- Audio capability depends on what is connected over eARC — results were measured
  with the soundbar attached.

## How to verify after a reinstall

Play the file, then read the ffmpeg arguments of the session it created:

```bash
ssh homelab
docker exec jellyfin sh -c 'ls -t /config/log/FFmpeg.*.log | head -1 | xargs \
  grep -aoE "/usr/lib/jellyfin-ffmpeg/ffmpeg .*"' | tr " " "\n" | grep -E "codec:|hls_"
```

- `-codec:v:0 copy` / `-codec:a:0 copy` — stream passed through untouched
- `-codec:a:0 libfdk_aac` or `ac3` — audio re-encoded
- `-codec:v:0 h264_qsv` — video re-encoded
- `overlay_qsv` — subtitles being burned in
- **No session at all** — true direct play, the best outcome

A title generating dozens of sessions in minutes is the client restarting after
stalls, not normal playback.
