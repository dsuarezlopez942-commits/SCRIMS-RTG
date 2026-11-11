# SCRIMS RTG media assets

Upload your own Creative Destruction footage here. Keep these exact paths and filenames so the website can find the files.

## Full-page background
- `media/background.mp4` — muted, looped video behind the entire page. The existing animated background remains for reduced-motion, data-saving, or playback-failure cases.
  - Recommended: MP4 (H.264), 1280x720, 30 fps, no audio, below Cloudflare Pages' per-file limit.

## Main cinematic background
- `media/rtg-hero.mp4` — wide gameplay montage for the home hero.
  - Recommended: MP4 (H.264), 1920x1080, 10–25 seconds, muted/no voice, ideally under 25 MB.
  - The existing SCRIMS RTG banner remains as the poster/fallback.

## Highlights
Upload MP4 files with these exact names:
- `media/highlights/rtg-highlight-01.mp4` — featured highlight
- `media/highlights/rtg-highlight-02.mp4` — SOLO
- `media/highlights/rtg-highlight-03.mp4` — DUO
- `media/highlights/rtg-highlight-04.mp4` — SQUAD

Recommended: 720p or 1080p, H.264 MP4, 10–60 seconds each, compressed for fast loading.

## Upload with GitHub
1. Open the SCRIMS-RTG repository.
2. Choose **Add file → Upload files**.
3. Upload `rtg-hero.mp4` into the `media` folder (create the folder if needed).
4. Create `media/highlights` and upload the four highlight files there.
5. Commit the changes to the `main` branch.

Use gameplay footage you own or have permission to publish. Do not upload private player clips without their permission.
