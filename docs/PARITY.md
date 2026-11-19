# PARITY.md — Favorites (vanilla JS, Capacitor) to Flutter

Source root: `C:\Users\rookp\Documents\vkte\favorites-app`. Source files are `src/js/NN-*.js` and are merged in name order. Section 6 lists the invariants.

## 1. Data model

### 1.1 Performer record (IndexedDB `favlib`.`recs`, keyPath `id`)

Photos are stored separately (see 2.1). In memory `photos` and `thumb` are URL strings.

| Field | Type | Meaning | Source |
|---|---|---|---|
| id | string | `crypto.randomUUID()`. Must match `/^[\w.:-]{1,128}$/` (`safeId`) on import and sync. | 01a |
| name | string | Required, trimmed, at most 300 characters on import. | 03, 18 |
| aliases | string | Comma-separated, split on `,` or `،`. | 03 |
| country | string | Free text. | 03 |
| birth | string | `YYYY-MM-DD` from the date input, or empty. May be partial in imported data. Drives the +18 gate. | 03, 01b |
| works | Work[] | See 1.2. | 01c |
| tags | string[] | Free-form. The form splits on `,` or `،`. | 03 |
| notes | string | Free text. | 03 |
| photos | string[] | At most 30 (MAXPH). First is primary. | 01c |
| thumb | string | Thumbnail of `photos[0]`, 640 px long side, q .86. | 01c |
| thumbV | number | `3` means the thumbnail has been upgraded to 640 px. | 01c |
| lists | string[] | Ids of performer lists. | 01b |
| rating | number | 0 to 5 in 0.5 steps. With `criteria` it is the mean of the filled values rounded to 0.5. | 03 |
| criteria | object or null | Keys beauty, charisma, perf, seduce, body, screen, bold, heat, each 0 to 5. Legacy `chem` is migrated to `bold`. | 01c |
| bodyD | object or null | Keys face, hair, skin, figure, chest, waist, hips, legs, each 0 to 5. If bodyD and criteria are both on, `criteria.body` is the rounded mean of bodyD. | 03 |
| fav | bool | Favourite. | 02 |
| accounts | `{p,v}[]` | `p` is a platform key from PLAT, `v` is a username or URL. Empty `v` is dropped. | 01c, 03 |
| pdbId | string | ThePornDB performer id. | 03 |
| stashId | string | StashDB id. | 03 |
| ofId | string | OnlyFans username. | 03 |
| fsId | string | Fansly username. | 03 |
| srcImgs | string[] | Source URLs of photos that were downloaded. | 03 |
| source | string | Provenance, for example `ThePornDB + StashDB (راجعتُه يدويًا)`, `إدخال يدوي`, or `X (اقتراح ذكي)`. | 03, 04 |
| worksAt | number | Timestamp of the last works refresh. | 02 |
| height | number | Height in cm, filled from StashDB. | 02 |
| cs | number | Career start year. | 02 |
| ce | number | Career end year. | 02 |
| added | number | Creation timestamp. Set to `updated` if missing. | 01c |
| updated | number | Last-modified timestamp. Drives sort, import conflict resolution and sync. | 01c |
| views | number | Detail-page open count. Device-local, not synced. | 22 |
| lastView | number | Timestamp of the last open. Device-local, not synced. | 22 |
| elo | number | Duel rating, default 1000. | 23 |
| duels | number | Duel count. | 23 |
| dw | number | Duel wins. | 23 |
| tier | string | One of `S`, `A`, `B`, `C`, `D`. | 23, 26 |
| nph | number | Photo count in the stored row only. Deleted on read. Not synced. | 01b |

Two rules apply to the performer record.
- `normItem` runs on load and import: convert string works to structured works, migrate `chem` to `bold`, default `photos`, `tags` and `lists` to `[]`, and set `updated` and `added` if missing.
- Unknown fields must survive round trips. Import spreads `...x`, and the form spreads `...it`.

### 1.2 Work (item of `works[]`)

Normalised by `normW` in 01c. A work is identified across performers by `wKeyOf(w) = wkey(t) + '|' + wkey(s)`. `wkey` is the lowercase title with only letters and digits kept (Unicode).

| Field | Type | Meaning |
|---|---|---|
| t | string | Title. Required. |
| s | string | Site or studio. |
| y | string | Four-digit year. |
| d | string | `YYYY-MM-DD`. `ydOf` accepts `YYYY-M-D`, `D-M-YYYY`, `YYYY-M`, or `YYYY` alone. |
| w | 1 | Watched. |
| wd | `YYYY-MM-DD` | Watch date. Set to today when marked watched. |
| r | number | Work rating, 1 to 5. |
| rec | 1 | Recommended. |
| q | 1 | In watchlist (🔖). |
| upc | 1 | Marked upcoming. Counts only if not watched. |
| fav | 1 | Favourite work. |
| n | string | User note. |
| a | number | Added-at timestamp. Drives the "new" badge. |
| p | https URL | Poster. |
| du | int | Duration in minutes. A source value above 180 is treated as seconds and divided by 60. |
| ds | string | Description, at most 320 characters (280 when fetched). |
| u | https URL | Page link. |
| tg | string[] | Work tags, deduplicated, at most 10 (8 when fetched). |
| ls | string[] | Ids of work lists (`wlists`). |
| ip | `[A-Za-z0-9-]{1,64}` | ThePornDB scene id. |
| is | same pattern | StashDB scene id. |
| im | `tt\d{5,10}` | IMDb id. |
| tm | `\d{1,10}` | TMDB id. |

Predicates and helpers:
- `isUpcoming(w)`: `w.upc && !w.w`, or `d > today`, or (no `d` and `y` > current year).
- `isRecent(w)`: `d <= today`, or `y <= current year`.
- `wDate(w)` is `d`, else `y-01-01`.
- `daysUntil(d)` is the number of days from today to `d`.
- On import and sync, `safeWorks` deletes unsafe `p` and `u`. `safeImg` allows only `https?://` or `data:image/(png|jpe?g|webp|gif|avif);base64`, with no `"<>\`` or backslash.
- Legacy string works import as lines `title | site | year` or `title (YYYY)`.

### 1.3 Other entities

- **List** (`vkte_lists`): `{id, name}`.
- **Work list** (`vkte_wlists`): `{id, name}`. Works reference them through `ls`.
- **Wish entry** (`vkte_wish`): `{n, t}`, at most 500. It is removed automatically when a performer with that name is saved.
- **Work group** (derived by `wAll()`, a cache): `{key, t, s, d, y, dt, r, rec, fav, seen, q, upc, wd, n, p, du, ds, u, tg, ls, a, who[], refs[{it,idx,w}]}`. It merges works that share a key across performers. The first non-empty value wins, and `r` is the maximum.

### 1.4 Smart filters (performers, from `SMART` in 01c)

| Key | Rule |
|---|---|
| top | rating >= 4.5 |
| unrated | no rating |
| unseen | at least one unwatched work |
| upcoming | has an upcoming work |
| recent30 | added in the last 30 days |
| nophoto | no photos |
| noworks | no works |
| nobirth | no birth date |
| bday | birthday this month |
| manyworks | 5 or more works |

### 1.5 Constants

- **CRIT** (criteria labels): beauty الجمال, charisma الكاريزما, perf الأداء, seduce الإغراء, body الجسم, screen الحضور على الشاشة, bold الجرأة, heat الإثارة.
- **BODY**: face الوجه, hair الشعر, skin البشرة, figure القوام العام, chest الصدر, waist الخصر, hips الأرداف, legs الأرجل.
- **PLAT** (account platforms: key, label, base URL):
  - instagram (`instagram.com/`)
  - x (`x.com/`)
  - tiktok (`tiktok.com/@`)
  - onlyfans
  - fansly
  - snapchat (`snapchat.com/add/`)
  - telegram (`t.me/`)
  - reddit (`reddit.com/user/`)
  - youtube (`youtube.com/@`)
  - twitch
  - linktree (`linktr.ee/`)
  - website (no base)
  - other (no base)
- **`accUrl(a)`**: if it is a full http(s) URL, use it. Otherwise strip `@` and `/` and build base+value, but only if the value matches `^[\w.\-]+$`. For website and other, accept a bare domain and prepend https. Otherwise return null.
- **`zodiac(birth)`**: 12 Arabic signs with fixed cut dates (الجدي through القوس).
- **Site badge**: hue from `HUES=[338,350,2,318,300,284,270,328][hash(site)%8]`, text is the first two initials. `hhash` is `h=(h*31+c)>>>0` over the lowercased string.
- **Image quality**: full 1800 px at q .9, thumbnail 640 px at q .86. Output is WebP if the browser supports it, else JPEG. Resize steps down by halves, with EXIF orientation applied.

## 2. Storage

### 2.1 IndexedDB `favlib` v1

| Store | keyPath | Content |
|---|---|---|
| `recs` | id | The record without `photos`, with `thumb` replaced by a stored value and `nph` added. |
| `photos` | id | `{id, list: [stored value...]}`. |
| `kv` | out-of-line | `bkman` (auto-backup manifest `{id: [photo filenames]}`) and `__blobtest`. |

- **Stored photo value**:
  - On device: `{f: filename, s: size, t: mime}`. Only the filename is kept because the base path changes between updates.
  - On web: a Blob if Blob storage works, otherwise a data-URL string. A probe writes `__blobtest`. On failure it sets LS `vkte_blob_off=1`.
  - Legacy: older versions stored Blobs inside the DB on device. These are migrated to files in the background (`DB.legacy`).
- **Photo files on device** (`FST`): `Directory.Library/photos/<uuid-without-dashes>.<webp|png|gif|avif|jpg>`. `gc()` runs 60 s after boot. It deletes unreferenced files older than 1 hour, and only if there is no legacy migration pending.
- **Save path** (`save()`): the single save point.
  1. Drop any record where `minorRec` is true, with a toast.
  2. Write the record plus its photos.
  3. Run `HOOKS.saved`.
  4. Return true or false.
- **Delete**: `DB.del(id)` removes both stores and runs `HOOKS.deleted`.
- **Hooks** (`HOOKS`): `saved(arr)`, `deleted(id)` and `meta()`. They drive auto-backup, sync scheduling, search cache invalidation, home refresh and wish cleanup.

### 2.2 localStorage keys (prefix `vkte_`)

**Included in backup (PREF_KEYS)**

| Key | Content |
|---|---|
| vkte_rec_saved | JSON array of saved-for-later suggestions. Merged as an array. |
| vkte_rec_ignored | Names the user marked as not their taste. Array, merged. |
| vkte_rec_feedback | Legacy learning data. |
| vkte_rec_fb2 | Learning model `{v:2, pos, neg, w, acc, rej, hist, log, migrated}`. |
| vkte_rec_ui | Suggestions-screen state. |
| vkte_rec_dx | `{div, expl, rep}`, each 0 to 2 (defaults 1,1,1). |
| vkte_bg | Auto-update mode: `wifi`, `any` or `off`. |
| vkte_dx_f | Discover quick filters `{age:'|a|b|c|d', conf:bool}`. |
| vkte_view | Library view: `'2'`, `'3'` or `'l'`. |
| vkte_sort | Library sort. |
| vkte_wview | Works view: `cards` or rows. |
| vkte_picknew | `1` or `0`: random pick only from unwatched works. |
| vkte_autoworks | `1` or `0`: weekly auto-refresh of works. |
| vkte_recent | JSON array of recent performer ids, at most 14. Array, merged. |
| vkte_open_app | `nuvio`, `stremio` or `custom`. |
| vkte_open_q | `title`, `site_title` or `who_title`. |
| vkte_open_tpl | Custom URL template containing `{q}` or `{raw}`. |
| vkte_theme | `dark`, `amoled` or `light`. |
| vkte_accent | `copper`, `rose`, `violet`, `teal` or `gold`. |
| vkte_wish | Wish list. Array, merged. |
| vkte_goal | Weekly watch goal, 0 to 99. |

**Not in backup**

| Key | Content |
|---|---|
| vkte_key | ThePornDB API key. |
| vkte_stash | StashDB API key. |
| vkte_ofapi, vkte_fsapi | OnlyFansAPI and Fansly API keys. |
| vkte_ofapi_base, vkte_fsapi_base | Base URLs for those two APIs. |
| vkte_ofapi_cfg, vkte_fsapi_cfg | `{search, prof, auth}`. |
| vkte_proxy | Referenced in a comment as untouched by VX. |
| vkte_pin2 | `{s: salt-hex, h: sha256hex(salt+"|"+pin), n: length}`. |
| vkte_pin | Legacy PIN, deleted on set. |
| vkte_lockf | `{f, u, t}`: failed attempts, locked-until, last time. |
| vkte_auto | `1`: lock on leaving the app. |
| vkte_cover | `1`: cover the screen in the background. Default on. |
| vkte_lists | Lists. Synced and merged in backup, but not in PREF_KEYS. |
| vkte_wlists | Work lists. Same handling. |
| vkte_sync_code | TV 6-digit code. |
| vkte_sync_last | `{at, sent, photos, deleted, pulled}`. |
| vkte_sync_tv | Phone to TV link: `{h, k, auto, keys, at, err}`. |
| vkte_sync_base | Per-performer last agreed signature. |
| vkte_sync_vkte, vkte_sync_vkte_base | Link to the abandoned VKTE ONLY app. Keep it dormant. |
| vkte_tv | `1` or `0`: manual TV mode. |
| vkte_tv_auto | Auto-detected TV. |
| vkte_tvs | TV scale (0.85, 1, 1.15). |
| vkte_tv_anim | `1` or `0`. |
| vkte_tv_qh | TV search history. |
| vkte_tv_sp | Last 12 "surprise" picks. |
| vkte_wlast | Timestamp of last seen works (new-works dot). |
| vkte_first_seen, vkte_bk_snooze | Reminder bookkeeping in 05. |
| vkte_last_export | Time of the last export or auto-backup. |
| vkte_bk_at | Time of the last auto-backup. |
| vkte_errlog | Last 40 errors. |
| vkte_rel_last | New-release alert marker. |
| vkte_pick | JSON array of performer ids selected for the random pick. |
| vkte_mood | `{du, tg, s, fav, top}`. |
| vkte_studio_new | Count of new studio images. |
| vkte_studio_visit | Last Studio visit time. |
| vkte_rec_pool2 | Candidate pool `{v:2, at, round, list}`. |
| vkte_rec_cache2 | Displayed list `{list, at}`. |
| vkte_rec_attrs2 | `{perfId: {t, at:{c,e,hr,ey,cp,h,cs}, sid, pid}}`. |
| vkte_sd_caps2 | StashDB capability probe: `{v:1, g, fl, age, eth, hair, sort}`. |
| vkte_sd_studios2 | Studio name to StashDB id cache. |
| vkte_rec_seen | Not confirmed (06-recs not read). |
| vkte_rec_imp | `{key: [count, lastTs, 'YYYY-MM-DD']}`, kept 30 days. |
| vkte_rec_picks | Stable daily and weekly picks. |
| vkte_rec_prefs | `{amin, amax, xcc[], photo, minM}`. |
| vkte_bg_log | Last 30 scheduler decisions. |
| vkte_bg_try | Last Discover pre-warm attempt. |
| vkte_bg_disc | Last successful pre-warm. |
| vkte_blob_off | Disables Blob storage on web. |

### 2.3 IndexedDB `vkte_studio` v1 (Studio)

- **Stores**: `img` (keyPath `id`, index `pid`) and `kv`.
- **img record**:
  - `id`: `'i' + fnv(normalizedUrl) + fnv(reversedUrl).slice(0,4)`.
  - `pid`: performer id.
  - `url`: normalised, hash dropped, host lowercased.
  - `prev`: preview URL.
  - `src`: `tpdb`, `tpdbs`, `stash`, `stashs` or `wiki`.
  - `kind`: `portrait`, `promo`, `still` or `archive`.
  - `w`, `h`, `bytes`: dimensions and size.
  - `sess`: `{k, t, d, st}` (key `tpdb:<id>` or `stash:<id>`, title, date, studio), or null.
  - `pub`: date.
  - `page`: source page URL.
  - `found`: timestamp.
  - `seen`: number.
  - `like`: number.
  - `hide`: 0 or 1.
  - `albums`: id array.
  - `dh`: 64-bit dHash as 16 hex characters, or `'-'` if it failed.
  - `col`: dominant colour.
  - `probed`: timestamp.
  - `bad`: failure count.
  - `dupOf`: id of the better copy.
  - `dups`: number of copies.
  - `wrong`: flag.
- **kv keys**:
  - `settings`: `{freq:'12h'|'day'|'week'|'manual', src:{tpdb,tpdbs,stash,stashs,wiki}, minPx, perMax:600, probe:24, keepOnRemove, pages:4}`.
  - `albums`: `[{id, name, ids[]}]`.
  - `shown`: `{imgId: 'YYYY-MM-DD'}`, pruned at 120 days.
  - `perfAt`: `{pid: ts}`.
  - `status`: `{last, added, errs[], reqs}`.
  - `wrong`: `{normalizedUrl: 1}`.
  - `hiddenSrc`: `{src: 1}`.
  - `picks`: `{'tag|period': [ids]}`.
- **Visibility rule**: not hidden, not wrong, not a duplicate (`dupOf`), source not hidden, performer still exists, and `minPx` respected.
- **Scoring**:
  - `quality = min(100, log2(px/1e5+1)*18)`, minus 25 if the short side is under 500. With no dimensions it is 40 for stash or wiki, else 30.
  - `rarity` = no duplicates +25, archive +30, still +12, age bonus up to 30 (3 per year since publish), unseen +20, and a source bonus (wiki 20, stashs 10, tpdbs 6, stash 4).
- **Duplicates**: same performer, dHash Hamming distance <= 4 and aspect within 2%. For images in the same session it must be exactly 0. The highest resolution is kept. `similar()` uses a distance <= 14.

### 2.4 Auto-backup folder (native only)

`Documents/FavoritesBackup` (fallback `Directory.Data`):
- `items/<safeId>.json`: the record with `photos` and `thumb` as `file:<name>` references.
- `photos/<safeId>-<idx|t>-<size>.<ext>`.
- `data.json`: `{app:'favlib-backup', v:1, at, count, ids[], lists, wlists, prefs}`.
- `import/` and `exports/`: drop-in and output folders.
- `.probe`: write test file.

Behaviour:
- It is debounced 4 s after a save and runs on leaving the app. A full pass runs 5 s after boot. It is disabled in TV mode.
- Restore runs on first boot when the DB is empty and `data.json.ids` is non-empty.
- The restore gate skips minors.

## 3. Backup and sync

### 3.1 Manual backup JSON (`Backup.exportNow` and `importJson`, 18-backup.js)

File: `favorites-backup-YYYY-MM-DD.json`. It is written in chunks:

```
{"app":"vkte-favorites","v":5,"exportedAt":<ms>,"lists":[...],"wlists":[...],"prefs":{<PREF_KEYS with non-empty values as raw strings>},"items":[ <record with photos[] and thumb as data:URI base64>, ... ]}
```

- There is no separate meta block. `exportedAt` is the only metadata.
- **Encrypted variant** `.vkte`: `{app:'vkte-enc', v:1, salt:b64(16), iv:b64(12), data:b64(AES-GCM(ciphertext of the JSON above))}`. The key is PBKDF2-SHA256 with 200000 iterations and a 256-bit key, with a minimum password length of 8. It stays compatible with old `restore.vkte` files.
- **Import rules** (`importJson`):
  - Requires `Array.isArray(items)` and at most 50000 items.
  - Each item must be an object, have `safeId(id)`, and a non-empty string `name`.
  - Per item: name at most 300 characters. Photos are `safeImg`, under 40 MB and at most 30. `tags` must be strings, at most 100. Works are at most 5000 and run through `safeWorks`. `thumb` goes through `cleanImage`.
  - Minors (`minorRec`) are skipped and counted.
  - New ids are added.
  - An existing id is replaced only if the file's `updated` is newer. Otherwise, if the local photos are incomplete, the file's photos are taken and the other fields kept.
  - Nothing is ever deleted.
  - Lists and wlists are merged by id. Prefs are merged: array keys (`rec_saved`, `rec_ignored`, `recent` (cap 14), `wish`) by union, others only if currently empty. If prefs changed, the page reloads after 1.5 s.
  - A confirmation dialog shows counts first.
- Import sources: file picker (limit 900 MB), the backup folder `import/` and `exports/`, and an http(s) URL.
- API keys and the PIN are never exported.
- **CSV export** (works hub, 08): UTF-8 with BOM. Headers: العنوان, الممثلات, الموقع, التاريخ, المدة (د), التقييم, شوهد, تاريخ المشاهدة, للمشاهدة, أنصح به, وسوم, قوائم, ملاحظة.

### 3.2 Phone to TV sync (31-sync.js and ShellPlugin.java)

**Transport**
- Plain HTTP on the LAN. The TV (Android only) runs a `ServerSocket` on port 8765, trying up to +5 until one is free. The default is 8765. The VKTE ONLY link uses 8766.
- Pairing link: `favlib://pair?h=<ip>:<port>&k=<code>`, shown as a QR code (qrcode-generator, type M).
- Manual pairing: enter the IP (port defaults to 8765) and the code.

**Authentication**
- The query parameter `?k=<6-digit code>` is checked on every request before any body is read. The code is generated from `crypto.getRandomValues` (100000 to 999999) and stored in LS `vkte_sync_code`. It can be regenerated, which calls `Shell.setToken`.
- The comparison is constant-time.
- The lockout is cumulative: 12 failures from one peer, or 30 global within 10 minutes, gives 429 `locked` for 10 minutes.
- A wrong code gives 401 `{"error":"code"}`.

**Server limits**
- 8 concurrent connections.
- Maximum body 96 MB (413 if larger).
- Socket timeout 90 s.
- JS reply timeout 100 s (504 `timeout`).
- CORS is open (`*`). `OPTIONS` returns 204.
- The response is always JSON, and the status line text is always "OK".

**Endpoints** (all need `?k=`)

| Endpoint | Behaviour |
|---|---|
| `PUT or POST /photo/<name>` | Body is the raw base64 of the image. Name must match `^[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|webp|gif|avif)$`. It is written natively to `photoDir` through a `.part` file and rename. Response: `{ok:true, size}`. It never reaches JS. |
| any other request | Passed to JS as a `request` event `{id, method, path, query, body}`, answered through `Shell.respond({id, status, body})`. |
| `GET /hello` | `{app:'favlib', v:1, name, count, sig:{id:[sigHash, updated]}, photos:[filenames on TV]}`. |
| `POST /get` | Body `{ids}`. Response `{items:[wire items]}`. |
| `POST /items` | Body `{items:[wire]}`. The server validates `safeId`, a non-empty name, and `!minorRec`. It resolves `{f,s,t}` photo refs to local files only if the name matches `PH_RE`. Otherwise it keeps a `safeImg` string, else drops it. It then runs `safeWorks` and `normItem`. It preserves the local `views`, `lastView` and `nph` fields. It replaces or appends and writes through a serialised queue. Response `{ok:true, n}`. |
| `POST /delete` | Body `{ids}`. Response `{ok:true, n}`. |
| `POST /meta` | Body `{lists, wlists, prefs}`. Lists must have a `safeId` and a name. From prefs only `vkte_wish`, `vkte_goal`, `vkte_key` and `vkte_stash` are accepted, and only if they are strings. |
| `POST /done` | Body `{sent, photos, deleted, pulled}`, clamped to 0..1e7. Saves `vkte_sync_last`, refreshes the TV UI and shows a toast. |

**Wire item**
- The full record minus the device-local fields `views`, `lastView` and `nph`.
- `photos` and `thumb` become refs `{f, s, t}`. For a file on device that is the stored filename. For a blob or data photo it is `w<h2(id:idx:size:type)>.<ext>`.
- **Signature** `sig(it)`: `h2(JSON(wire without updated, thumb, thumbV))`. `h2` is a 32-bit FNV-1a variant combined with a djb2 hash, in base 36, plus the length in base 36.

**Phone algorithm** (`syncNow`, one run at a time, with a queue)
1. `GET /hello`. It must report `app === 'favlib'`.
2. Pull (TV to phone, two-way only). A record is pulled if it exists locally and its signature differs from the TV's. The decision is three-way against the stored base signature:
   - `base === local` means only the TV changed, so pull.
   - `base === remote` means only the phone changed, so do not pull.
   - If both changed, the newer `updated` wins.
   Pulls are fetched 25 ids per `/get`. A pulled record keeps the local photos and thumb and the device-local fields, skips minors, and is applied only if the local signature is unchanged since the start.
3. Push. For each record not pulled whose signature differs from the TV's:
   - upload each missing photo with `PUT /photo/<f>?k=` (base64 body), skipping names listed in `hello.photos`;
   - batch `/items` at 20 records or 1.5 MB.
4. Delete: ids present on the TV but absent locally go to `/delete`.
5. Meta: `/meta` with `{lists, wlists, prefs:{vkte_wish, vkte_goal, plus vkte_key and vkte_stash only if cfg.keys && twoWay}}`. Then `/done`.
6. Store `base[id]` for every record both sides agree on. Save `cfg.at`.

**Scheduling**
- Auto sync fires 5 s after a save, delete or meta change, 1.5 s after the app resumes, and 8 s after boot.
- It is skipped when offline.
- Failure retry back-off doubles from 30 s up to 15 minutes.
- Error messages (Arabic): 401 means wrong code, 429 means too many attempts so wait 10 minutes, otherwise the screen is unreachable.
- Transport: `CapacitorHttp` natively (connect 6 s, read 120 s, `Content-Type` `text/plain` for string bodies), `fetch` on web.
- The VKTE ONLY link is one-way (phone to app, `twoWay:false`). The project says that app was cancelled, so treat it as dormant.

**Shell plugin methods (Android)**

| Method | Behaviour |
|---|---|
| `info` | `{tv, sdk}`. TV is true if leanback, television, or no touchscreen. |
| `secure({on})` | Sets or clears `FLAG_SECURE`. |
| `voice({lang:'ar-SA', prompt})` | Runs the speech recogniser and returns `{text}`. |
| `startServer({token, photoDir, port})` | Returns `{ip, port}`. |
| `setToken({token})` | Replaces the token and clears the failure counters. |
| `address` | Returns `{ip, port}`. |
| `stopServer` | Closes the socket. |
| `respond({id, status, body})` | Completes a pending request. |

Local IP selection prefers a site-local address on a `wlan` or `eth` interface.

**Capacitor config**: appId `com.favlib.app`, appName Favorites, webDir `www`, background `#15101f`, `CapacitorHttp.enabled`, iOS `contentInset:'never'`. Plugins used by native code: `@capacitor/core`, `app`, `filesystem`, `share`, `CapacitorHttp`.

## 4. Features and screens

Format: feature (file). Navigation is a bottom dock (`nav.dock`) with the buttons 🏠 الرئيسية (`nDash`), المكتبة (`nHome`), الأعمال (`nWorks`, with a new-works dot), اكتشف (`nRecs`), الاستديو (`nStudio`, with a dot) and المزيد (`nMore`), plus a floating add button (`bAdd`). Pages are overlays and act as tabs: opening one closes the others.

### 4.1 Boot, shell and onboarding

- **Boot** (99): apply view, lock immediately if a PIN exists, load DB, run `normItem` and save migrated records.
  - If the DB is empty, `tryRestore` from the backup folder.
  - Render the library, then open Home on mobile only.
  - Background tasks: thumbnail backfill at 0.9 s, full auto-backup pass at 5 s, photo GC at 60 s.
- **Onboarding** (22): an empty library shows a welcome card with "أضف أول ممثلة" and "استيراد نسخة احتياطية". There is no multi-step tutorial.
- **Back handling** (17): the order is Gallery, then lock (ignored), then ask-dialog, then top overlay.
  - A page overlay returns to Home.
  - A selection mode is cancelled.
  - Scroll to top if scrolled more than 260 px.
  - Otherwise open Home.
  - The Android back button minimises the app at the root. In TV mode it maps to Escape.
- **Keyboard**: `Esc` goes back, `B` or `ب` toggles blur. Left and right arrows in the detail page switch to the previous or next performer (07). More shortcuts are in 10 (partial).
- **Themes** (21): theme `dark`, `amoled` or `light`, with background colours `#15101f`, `#000`, `#f5f0ec`. Accent `copper`, `rose`, `violet`, `teal` or `gold`.
- **Dialogs** (01c): `askShow`, `askText`, `askConfirm` and `askNote`. A toast lasts 2.4 s. A busy overlay has an optional stop button.
- **Easter-egg-style settings**: an error log (07), a "versions" label, and the "diagnostic response" tools for ThePornDB and StashDB (03).

### 4.2 Home dashboard (22-home.js)

A spotlight card shows today's pick. It is chosen by `hhash(today)+skip` over favourites or performers rated 4 or more (at least 3 of them), else all performers with a photo. It offers open, slideshow and next. Below it are four stats buttons (performer count, favourites, works, watched percent) and four tiles (duel, tier, rate session, random pick).

Then the weekly goal card (25). Then shelves, each shown only if non-empty and capped at 12 to 14 items:
- في مثل هذا اليوم (watched on this date in earlier years)
- تابعت مؤخرًا
- المفضلات ★
- أعمال قادمة ⏳
- قائمة المشاهدة 🔖
- مقترحات تناسب ذوقك 💡
- الأعلى تقييمًا
- ترتيب المواجهات
- أعياد ميلاد قريبة (within 45 days)
- صدر حديثًا ولم تشاهده
- أضيفت حديثًا
- الأكثر زيارة (views > 1)
- بانتظار تقييمك

Each shelf header has a "عرض الكل" jump. The header has search, add and settings buttons. It re-renders 0.7 s after data changes when idle. Opening a detail page increments `views` and sets `lastView`, saved after a 4 s debounce.

### 4.3 More page (index.html 87-109)

Tiles: القوائم, الإحصائيات, المواجهة, المستويات, الشاشة (sync), الاستوديوهات, جلسة تقييم, ملخص السنة, الإنجازات, قائمة الانتظار, أعياد الميلاد, سحب عشوائي, عرض شرائح, مقارنة, الوسوم, تمويه الصور, قفل الآن, الإعدادات. Four tiles are added by 33: نشاطي, في مثل هذا اليوم, مزاج الليلة, اكتمال المكتبة.

### 4.4 Library (02-library.js, 07, 37)

- **Header**: slideshow, random pick, view toggle (2 columns, 3 columns, list), blur, lock, settings, a count `N ممثلة · M عمل`, and a search box.
- **Search** (120 ms debounce) runs over name, aliases, country, tags, notes, work titles and sites, and account values.
- **Sorts** (index.html): recent (default), rating, name (Arabic locale), added, oldest, works count, youngest (birth descending). The sort persists in `vkte_sort`.
- **Filters**: chips for favourites, a single list, a smart list, and a tag.
- **Card**: photo with a rating badge, photo dots, a favourite star, name and country. Cards render in chunks of 30 (15 on TV). A card cycles its photos every 7 s on up to 4 visible cards while idle.
- **Recommendation bar** above the grid: "اقتراحات تناسب ذوقك".
- **Lists sheet**: covers made from up to 4 member thumbnails, member count and average rating, rename, delete (members keep their record), new list, a manage-members picker (07), and smart-list chips with counts.
- **Multi-select, merge duplicates, quick sheet, and previous/next in the detail page** are in 07 (partial).

### 4.5 Performer detail (02, 33, 10, 11)

- **Hero**: swipeable carousel with dots, a blurred background that follows the current photo, 3.8 s auto-advance with a pause button (held for 9 s after touch, and stopped when scrolled more than 380 px), and a fullscreen viewer on tap. Name, stars and rating.
- **Sections**:
  - criteria bars;
  - body details with average;
  - info grid: aliases, country, birth and age, zodiac, height, career, photo count, works with watched count, sites, added, updated, source;
  - accounts as links;
  - tags and lists;
  - notes;
  - career block (33);
  - similar performers in the library (10).
- **Works section**: filter chips (all, recent, upcoming, top rated, recommended), site chips, a search box when there are more than 12 works, and an 8-row limit with "show all". Each row has a site badge, title, meta (site, date, duration), a 5-star rating, a watchlist toggle (🔖), a recommend toggle, and a watched toggle (stamps `wd`). The "تحديث" button runs `refreshAll`. The works list auto-refreshes if the performer is linked, `vkte_autoworks` is `1`, and `worksAt` is older than 7 days.
- **Actions**: favourite, edit, delete (with undo toast and restore).
- **Streaming open** (11): the "open in app" action depends on `vkte_open_app`.
  - Nuvio: no URL scheme is generated. The title is copied to the clipboard.
  - Stremio: `stremio:///search?search=<q>`.
  - Custom: a template, with `javascript:`, `data:` and `vbscript:` blocked.
  - Query forms: title, site plus title, or first performer plus title.
  - Also: copy name, copy link, and a "new release" alert (rest not read).

### 4.6 Add and edit form (03-forms.js)

- **Fields**: name (required), aliases, country, birth (date picker), accounts (add by platform chip), works (rows with title, site with a datalist, and `YYYY` or `YYYY-MM-DD`), bulk paste ("title | site | year" per line), tags, photos (multi-file picker, up to 30, tap to make primary), photo URLs one per line (fetched through `fetchImage` then resized), a Google image-search shortcut, overall star rating or the 8 criteria (mean to 0.5), optional body details (8 star pickers whose mean feeds `criteria.body`), list checkboxes with a "new list" field, notes, and a mandatory adult-confirmation checkbox.
- **Fill from ThePornDB**: search by name (up to 10 results, 18+ filtered), pick, fills all fields, sets `pdbId`, downloads up to 6 images, and fetches works.
- **Fill from StashDB**: same, but fills only empty fields, merges aliases without duplicates, adds social accounts, adds images, and fetches works. Optional extra-source fill is injected through `VX` (OnlyFans and Fansly).
- **Works fetch buttons** call `fetchWorksFor` (ThePornDB) or `sdWorks` (StashDB) and merge with `mergeWorks`.
- **Save rules**:
  - Name required. Adult checkbox required.
  - Age under 18 or an unreadable date blocks the save.
  - Duplicate name warning (add only).
  - Thumbnail is reused if the first photo is unchanged.
  - A new list is created and attached.
  - `source` is rebuilt from the sources used, plus " (راجعتُه يدويًا)".
  - On a save failure the form stays open and the change is rolled back.
- **Photo pipeline**: `resize` (full image), `mkThumb`, `fetchImage` (native `CapacitorHttp` as a blob with a magic-byte MIME check, or `fetch` on web).

### 4.7 Works hub (05, 08, 11, 24, 25)

- **Tabs** (WTABS): الأحدث, القادمة, للمشاهدة, لم أشاهدها, الأفضل, الأقسام.
- **Sub-views of Recent**: الأحدث إصدارًا, آخر 30 يومًا, إصدارات <year>, مضافة حديثًا, الكل.
- **More tab sections**:
  - Collabs (works shared by 2 or more performers).
  - Sites with watched and rating share.
  - Watch diary grouped by month.
  - Release calendar: a month grid starting on Saturday with Arabic weekday names, per-day counts, upcoming marks, and a per-day list.
  - Work lists (wlists).
- **Hero** "🎲 اقتراح السهرة لك": a suggestion with details, watched, another, and hide.
- **Filters**: search (title, site, note, description, tags, performer names and aliases), site, performer, tag, year, work list, sort (date desc, old, rating, performer rating, added, duration, title), and a card or row view (`vkte_wview`).
- **Status filter** (08): all, unrated, rated, has note, no list, no tag, no image. A stats strip shows average rating, unrated count, watched time and remaining time (default 30 min per work when `du` is missing).
- **Bulk operations** (08): enter selection mode (also by long-press), select visible or none, then:
  - mark watched or unwatched;
  - add or remove the 🔖 watchlist flag;
  - recommend;
  - rate 1 to 5 or clear;
  - add to or remove from a work list (or create one);
  - add a tag;
  - delete, with a 10 s undo bar.
  A single save is issued for all touched performers. Export CSV or copy titles, either of the selection or of the current results.
- **Work sheet** (`wSheet`): cover, title, meta, performer chips, add a co-star, work rating, watched, watchlist, recommend and upcoming toggles, watch-date picker, description, tag editor, work-list chips and new list, a note field, and more (rest not read). `wEnrichScene` fills only empty fields by searching ThePornDB `GET /scenes?q=<title>&per_page=5`, then StashDB `queryScenes(term)`.
- **Add upcoming work** and **scan sources**: the upcoming tab has "＋ عمل قادم" and a source scan.
- **Radar** (`wRadar`): refresh every linked performer with a 320 ms gap, then `sdUpcoming()`, which asks StashDB for scenes with a release date after today for all linked performers (50 per page). Those are merged with `upc:1`.
- **Streaming play shortcut** (▶) on cards and rows (11).
- **Compare** (two performers side by side) and **tag manager** (rename, merge, delete) are in 05 lines 826 to 935.

### 4.8 Statistics (04-analytics.js, 10)

Two tabs: 📊 الإحصائيات العامة and 💡 الاقتراحات الذكية.

Overview cards:
- count grid: total, favourites, rated, mean rating, photos, works, sites, lists, watched, with body details;
- quick insights;
- criteria radar and per-criterion means;
- rating histogram in 0.5 bins;
- top 10 rated;
- best performer per criterion;
- age bands 18–24, 25–29, 30–34, 35–39, 40+, with youngest and oldest;
- countries with mean rating;
- top sites;
- tag cloud;
- additions over the last 6 months;
- list sizes;
- profile completeness percentages;
- awaiting-rating list;
- body radar and means;
- watch progress;
- works by year (last 10);
- best tags by rating (at least 2 rated);
- least complete profiles (out of 11 checks);
- account platforms.

A watch-pace card was added in 10.

### 4.9 Discover and recommendations engine (04, 26, 34, 06 not read)

**Taste profile** (`buildTasteProfile`)
- **Weight per performer** (`perfWeight`): base 0.3, plus 1.0 if favourite, plus `(rating-3)/2*1.3` (or from criteria and bodyD if unrated, `(avg-3)/2*0.8`), plus `min(0.6, 0.04*watched + 0.08*liked works)`. It is clamped to [-1.5, 3.2], and 26 and 34 widen that.
- **Extra signals** (26): tier S +1.3, A +0.8, B +0.3, C -0.1, D -0.6; duels >= 3 adds `clamp((elo-1000)/160, -0.8, 1.1)`; views > 2 adds `min(0.5, log2(views)/10)`.
- **Extra signals** (34): recently viewed adds `0.45*(1-i/14)`; list membership adds `min(0.24, 0.12*n)`. The final clamp is [-1.8, 4].
- **Features per performer**: country code, ethnicity, hair, eye colour, cup bucket (small, medium, large), age (18 to 69), height (130 to 215), and years of experience.
- **Source of features**: the performer record, else the attribute cache, enriched from StashDB `findPerformer` (preferred) or ThePornDB. Up to 18 performers per run. Retry after 45 days if attributes were found, else 7 days.
- **Category models**: country 1.0, ethnicity 0.8, hair 0.7, eyes 0.35, cup 0.5. Importance combines concentration (entropy) and confidence `n/(n+4)`. Negative weights subtract from affinity.
- **Numeric models**: age (base 1.0, floor 3, range 12), height (0.6, 4, 15), experience (0.4, 2, 10). Each is a weighted mean and deviation.
- **Studio and tag affinity**: built from work-level signals (watched ×1.5, rating factor, recommended ×1.8, favourite ×1.8) damped by `1/sqrt(works)`.
- **Confidence**: `nPos/(nPos+6)` × (0.55 + 0.45 × attribute coverage).

**Scoring** (`recScore`)
- Each feature gives a score in [-0.6, 1]:
  - categorical: affinity plus feedback adjustment;
  - numeric: Gaussian `exp(-0.5((v-mu)/(1.3*sd))^2)` plus a bucket adjustment;
  - studio and tag: only if the deep check found at least 3 scenes.
- Combine with importance times a learned multiplier (0.4 to 2.2).
- Raw is scaled by `0.6 + 0.4*min(1, coverage)`.
- A distant age reduces the score by up to 35%.
- Co-star bonus is at most +0.06.
- No image is -0.04.
- 26 adds a nearest-neighbours term from the top 80 weighted library performers: raw = 0.74×raw + 0.26×kNN.
- Match percent is `clamp(round(40 + raw*60), 40, 98)`.
- 04 also builds Arabic "why" strings from the strongest features.

**Learning**
- Positive and negative feedback keys accumulate (`country:`, `eth:`, `hair:`, `eyes:`, `cup:`, `age:`, `height:`, `exp:`, `studio:`, `tag:`).
- Weight updates use `+= 0.18*strength*err*(s-0.4)`.
- Adding a suggestion is a +1 signal. Ignoring is a -1 signal. Rating a performer added from suggestions later gives +0.5 (4 or more) or -0.8 (2.5 or less).
- The explore rate is 0.25 for fewer than 6 votes, else 0.15 if acceptance > 0.55, 0.30 if < 0.25, else 0.22. 34 scales it by [0.5, 1, 1.6] (cap 0.5).

**Candidate gathering** (`recGather`)
- StashDB: probe capabilities once (`sdCaps`: gender enum or criterion, field level 0 to 4, age, ethnicity, hair, sort). Then up to 7 attribute queries with `queryPerformers`, a world country rotation for exploration, and the top 3 studios' scenes.
- ThePornDB: top 2 studios through `/scenes?q=<studio>`, and top 2 tags through `/performers?q=<tag>&gender=female`.
- Optional VX extras: OnlyFansAPI and Fansly API.
- A pool refill runs when the pool is older than 3 days, or under 30 entries and older than 6 hours, or on forced refresh. After a refill the top 14 candidates get a deep check (up to 40 scenes: studios, tags, library co-stars). Otherwise the top 6.
- Candidates older than 21 days are dropped unless they have a deep check.

**Eligibility** (`recEligible`)
- Female only: gender must be present and equal to female.
- Age must be 18 or more and known.
- Not already in the library by name, alias or id. Not ignored.
- 34 adds: no source may show a minor, and not snoozed (shown too many times without interaction).
- The ranking rule is: best score, with a country-diversity penalty of 0.035 per repeat, plus a `shown` penalty of 0.025 each (cap 4), plus a diversification re-rank (lambda 0.03, 0.08 or 0.15).

**18–21 lane** (34): `verifyAge`.
- Requires a full valid date (year above 1900, not in the future) from a database source (stash or tpdb).
- All sources and fields must agree, otherwise it is rejected as a conflict.
- It is shown only if the exact age is 18 to 21 and `candAge` is also 18 or more.
- The age badge shows the source name or names.

**Discover lanes** (34): today's discovery, weekly picks (stable per day or week, with a per-country cap), 18–21, similar to your favourites, from your studios, new faces, outside the usual. The filter bar has age band chips and "المؤكدة فقط" (`confirmed` means 4 or more features with raw >= 0.5, or near a favourite with raw >= 0.45). The sheet actions are add, save for later, and not my taste. 26 adds preference controls (age range, excluded countries, require photo, minimum match), "similar to a performer", and "like" without adding. 34 adds a "learning controls" panel (diversity, exploration, repetition). A reset of learning exists in 26 (partial).

**Auto pre-warm** (36): `vkte_bg` is `wifi`, `any` or `off`. Blocks on offline, save-data, 2g, cellular when wifi-only, and battery under 20% unless charging. Pre-warm of Discover runs 40 s after boot (15 s on visibility), if results are older than 12 h and the last attempt was more than 1 h ago.

**Adding a suggestion** (`addRecToLibrary`): the 18+ checks (`candAge` and `adultOk`) run first.
- Duplicate name is refused.
- The record is built with `fav:true`, notes "تمت الإضافة بناءً على اقتراح ذكي (...)", `source` "<src> (اقتراح ذكي)", accounts from source URLs, and ids.
- The first image is downloaded and localised, then a thumbnail is made.
- Attributes are cached, learning is updated, the pool is trimmed, and works are fetched in the background.

### 4.10 Studio (32-studio.js)

- **Tabs**: اكتشاف, الأحدث, النادرة, الأفضل, الجلسات, الممثلات, أعجبتني, ألبوماتي.
- **Home picks**: photo of the day, today's selection (18, at most 3 per performer), hidden gem, week's best (24, at most 4 per performer), and a weekly session. Daily picks are seeded by Park–Miller from an FNV hash, so they are stable all day, and shown images are not repeated.
- **Sources**:
  - ThePornDB: `/performers/<id>` for the portrait and posters, and `/performers/<id>/scenes?page&per_page=50` for background (`still`) and poster (`promo`) images.
  - StashDB: `findPerformer{images}` and `queryScenes` sorted by DATE descending, 40 per page.
  - Wikimedia: Wikidata `wbsearchentities` and `wbgetentities`, requiring occupation `Q488111` and a matching birth year when both sides have one. Commons files come through `imageinfo`.
- **Throttling and budget**: 350 ms between calls, retries on 429 and 5xx, and a request budget of 220 (600 manual) per run. Pages are 4 on the first run (3 for StashDB scenes) and 1 afterwards.
- **Per performer**: only performers with a key and a linked id, or Wikimedia enabled. Order is oldest `perfAt` first. The run stops when the page is hidden. It pauses on 401 or 403 for that source only.
- **Smart albums**: 4K+, HD, 2020s, 2010s, before 2010, portrait, still, promo, archive, and by source (StashDB, ThePornDB, Wikimedia), plus "not yet seen".
- **Viewer actions**: like, hide, mark wrong, add to album, save (downloads the highest-resolution version), share, similar images, and versions of the same image.
- **Settings**: refresh frequency (manual, 12 h, day, week), auto-update mode (the same `vkte_bg`), source switches, minimum quality (0, 800, 1500, 2500), probe count (0, 12, 24, 60), per-performer cap (200, 600, 1500), keep or delete images when a performer is removed, unhide images, and clear the index (keeps likes and album images).
- Studio data is never synced and never in the backup. It is a separate DB (`vkte_studio`).

### 4.11 Gallery viewer (20-gallery.js, 15)

Fullscreen with two cross-fading layers. Swipe to navigate, double-tap or two fingers to zoom, swipe down to close. Slideshow every 4.5 s with a progress bar. The controls hide after 3 s while playing. Remote keys: left and right, OK for play and pause, back closes. It supports `opt.bar`, `onAction`, `onLoad`, `onShow` and `onClose` for Studio. A library-wide slideshow (`playLibrary`) uses the performers visible in the library.

### 4.12 Duel and tier (23-duel-tier.js)

- **Duel**: Elo with K = 32. Pairing picks the least-dueled of 5 random performers, then the closest Elo among 9 random others, avoiding the last pair. The pool is all, favourites, or a list. Tabs: play and board (top 100 with duel count and wins). Each vote stores `elo`, `duels` and `dw`. Haptic 8 ms.
- **Tier**: assign S, A, B, C or D, manually or automatically from rating (rest not read). Stored in `tier`.

### 4.13 Extras (25) and Plus (33)

- **Weekly goal**: 7-day watched count against `vkte_goal`.
- **Achievements**: 11 families with multiple levels:
  - collector 10/50/100/250;
  - critic 10/50/150;
  - watcher 25/100/500/1000;
  - streak 3/7/30 days;
  - work critic 10/50/200;
  - duels 20/100/500 (count is `sum(duels)/2`);
  - tiered 10/50;
  - photos 50/250/1000;
  - organiser 3/10 lists (lists plus wlists);
  - completer 10/50 (6 or more filled fields);
  - writer 5/25 notes on works.
- **Year wrap**: year chips, totals, watch time, performers added, busiest month, most watched performers, monthly bars, top studios and tags, and five-star works.
- **Rating session**: random queue of unrated performers (no rating and no criteria), with star rating, favourite, open and skip.
- **Wish list**: add by name (not if already in the library), remove, and turn into the add form. It is removed automatically on save.
- **Studios**: counts per studio (works, performers, watched percent, mean rating) with a drill-down.
- **Memories shelf**: works watched on today's month and day in earlier years.
- **Activity** (33): a GitHub-style heat map per year, with levels 0 to 4 (1, 2, 3 to 4, 5 or more), current and best streaks (the current streak stays alive if yesterday was watched), the busiest weekday, and a recent list.
- **On this day** (33): birthdays, watched, added to library, and released on this date.
- **Career** (33): shown on the performer page: years bar chart, status, top studios, co-stars in the library, watched share and mean rating.
- **Library completeness** (33): 7 checks (photo, full birth date, country, source link, rating, works, tags), an overall ring, and a filtered list.
- **Mood of tonight** (33): filters by duration (20/40/60), tag, studio, favourites and rating 4 or more. It scores and shows the top 3 with reasons. The state is saved in `vkte_mood`.

### 4.14 Random pick (03)

Choose performers (all, favourites, none, or by list; persisted in `vkte_pick`) and "unwatched only" (`vkte_picknew`). It draws a performer (preferring those with eligible works), then a work. Actions: search the title online, mark watched, another work, open profile.

### 4.15 Privacy, lock, blur (19, 03, 01a)

- **Lock**: 4 to 12 digit PIN, stored as SHA-256(`salt|pin`) with a 16-byte hex salt. The keypad has digits 0 to 9, delete and OK. It submits automatically when the length equals the PIN length. After 5 failures it locks for `min(300, 30*(fails-4))` seconds. Failures persist in `vkte_lockf` and reset after 1 hour. Auto-lock on leaving the app is optional (`vkte_auto`). The lock screen cannot be dismissed by back or Esc.
- **Cover** `vkte_cover`: the app switcher is hidden while backgrounded, and Android sets `FLAG_SECURE`. Both are on by default.
- **Blur**: a global toggle that blurs the grid, works, detail, lists, stats, pick, and TV UI.
- **Lock now** from the header or the More page.

### 4.16 Settings (index.html 124-200)

Sections:
- **Appearance**: theme and accent.
- **Lock and privacy**.
- **Backup and data**: export, import from file, folder, URL, encrypted export, backup now, find and merge duplicates.
- **ThePornDB**: key, test, auto-refresh works, and a response probe.
- **StashDB**: key and a probe.
- **OnlyFansAPI** and **Fansly API** (experimental): key, base URL, search and profile paths, and an auto probe.
- **TV mode**, **Screen and sync**, **VKTE ONLY**, **error log**.
- **Opening works in apps** (11).

### 4.17 Maintenance tools

- **Integrity check** (10): orphan list references, orphan work-list references, empty or corrupt photos, duplicate works within a record, implausible birth dates (under 18 or over 80), and nameless records. The fix merges duplicate works, keeping watched, rating and notes, and never deletes a performer or a work.
- **Data size and recompress** (10): heavy JPEG or WebP photos over 350 KB are recompressed (1800 px, q .88). Only kept if at least 15% smaller. Needs confirmation.
- **Merge duplicate performers** (07): groups by normalised name or alias (at least 3 characters), merged through a dialog.
- **Thumbnail backfill and upgrade** (01c): missing thumbnails first, then `thumbV:3` upgrades. Skipped on TV.
- **Undo for delete** (05): `undoToast`.
- **Error log** (07): the last 40 entries with counts, copy and clear.
- **Image reliability** (14, 15): failed images retry and fall back. Not read in detail.

### 4.18 TV app (30-tv-app.js, 13-tv.js)

- **Activation**: `vkte_tv=1`, or `?tv=1`, or auto-detect through `Shell.info().tv` (saved to `vkte_tv_auto`), or `vkte_tv=0` to force the phone UI. The TV UI hides the page overlays, and Backup and Sync are skipped in the TV UI.
- **Side nav pages**: بحث (on-screen keyboard plus voice via `Shell.voice`, with history `vkte_tv_qh`), الرئيسية (hero, spotlight and shelves), الممثلات (grid, loads more near the end), الأعمال, اقتراحات لك, استكشاف (swipe through performers: favourite, slideshow, new), الاستديو, مجموعاتي, ملفي (statistics and tiers), اتصال بالجوال (QR, IP, code, new code, import from URL or folder), الإعدادات. Sub-pages: performer page, compare pages (`cmp`), and layers for work, rating and recommendation.
- **TV settings**: UI scale (0.85, 1, 1.15), motion on or off, theme (dark or AMOLED), blur, lock now, clear search history, refresh works (radar), remote help, switch to phone UI. It shows version, library counts, WebView version and screen size.
- **Smart list for explore**: weight × 0.6, tag taste up to 1.2, days since last view up to 1.2, plus random 0.9. It shows a reason string. Surprise remembers the last 12.
- **Remote keys**: arrow keys move focus by a geometric nearest-neighbour search. A key repeat is throttled to one move per 95 ms and adds a `fast` class. OK or Enter opens, and a long press (550 ms) opens the quick layer. Menu, ContextMenu or `m` opens the quick layer on a card. Back is Esc, GoBack, BrowserBack, or Backspace outside inputs. Back closes a layer, then goes to the previous page and position, then the side nav, then minimises the app. Right arrow from the start of a row opens the side nav. Left or right in explore mode steps performers. Studio and Gallery capture keys when open.
- **Quick layers**: performer (open, favourite, rate and tier, compare, show photos), work (details, watched, watchlist, performer pages), recommendation.
- **Refresh**: the UI redraws 0.5 s after data changes. It waits while a layer is open.
- **Live sync**: on start the TV launches the sync server and opens the sync page if the library is empty.

### 4.19 Other

- **Motion** (35), **UX** (37): not read. 37 moves the slideshow and blur into a "⋯" menu on mobile.
- **Weekly works auto-refresh**: described in 4.5.
- **Birthdays page**: a list sorted by next birthday, with "turns N" and a countdown.

## 5. External APIs

**ThePornDB** (`https://api.theporndb.net`), with headers `Authorization: Bearer <vkte_key>` and `Accept: application/json`:
- `GET /performers?q=<name>`. Up to 10 shown.
- `GET /performers/<id>`.
- `GET /performers/<id>/scenes?page=<n>&per_page=100`. Up to 40 pages. 50 per page in Studio.
- `GET /scenes?q=<title|studio>&per_page=5|20&page=<n>`.
- `GET /performers?q=<tag>&gender=female&per_page=20`.
- Field mapping:
  - performer: `p.image`, `posters[]`, `face`, `thumbnail`, `extras.{birthday, nationality, birthplace, birthplace_code, gender, ethnicity, hair_colour, eye_colour, cupsize, measurements, height, career_start_year}`, `aliases`.
  - scene: `title`, `date`, `duration`, `site.name`, `tags[]`, `description`, `url`, `slug`, `background.*`, `posters.*`, `id`.
  - Error handling: 401 or 403 mean an invalid key. Paging uses `meta.last_page`.

**StashDB** (`POST https://stashdb.org/graphql`), with header `ApiKey: <vkte_stash>` and `Content-Type: application/json`. Body `{query, variables}`. 400 or 422 with an `errors` array raises a GraphQL error (`e.gql=true`) and triggers the field fallbacks:
- `searchPerformer(term, limit){id name aliases birth_date country urls{url} images{url width height}}`.
- `findPerformer(id){height career_start_year career_end_year}`, and the Studio variant with `images`.
- `queryScenes(input:{performers:{value:[id], modifier:INCLUDES}, page, per_page:100})`. Fields `id title release_date|date duration details studio{name} images{url width height} tags{name}`, with three fallback field sets and `release_date` falling back to `date`.
- `queryScenes` with `date:{value, modifier:GREATER_THAN}` for upcoming works (50 per page), with a fallback query.
- `queryScenes(input:{term, page:1, per_page:5})`, `queryScenes(input:{studios:{value:[id], modifier:INCLUDES}, page, per_page:25})`, `searchStudio(term, limit:3){id name}`.
- `queryPerformers(input:{gender:FEMALE | gender:{value:FEMALE,modifier:EQUALS}, country:{value, modifier:EQUALS}, age:{value, value2, modifier:BETWEEN}, ethnicity, hair_color, sort:SCENE_COUNT, direction:DESC, page, per_page})`, whose capability probe is cached in `vkte_sd_caps2`.

**Wikimedia**: `wikidata.org/w/api.php` (`wbsearchentities`, `wbgetentities`) and `commons.wikimedia.org/w/api.php` (`imageinfo`, `iiurlwidth=640`), `origin=*`, JSON.

**OnlyFansAPI** and **Fansly API** (experimental): configurable base URLs. Defaults are `https://app.onlyfansapi.com/api` and `https://app.apifansly.com/api`, with several candidate search and profile paths. Authentication tries `Bearer` first, then `X-API-Key`, and remembers the working one. Results are accepted only after StashDB or ThePornDB confirms gender and 18+.

**Images**: external image URLs are fetched with `CapacitorHttp` (native, as a blob, with a magic-byte MIME check) or `fetch`.

**Where the +18 gate (minorRec, sdAge, adultOk) is applied**
- Central save (`save()`): `minorRec` drops records (01b).
- Import, restore, auto-restore and sync receive: `minorRec` (18, 31, 18).
- Form: age check on the saved birth date, plus the adult checkbox (03).
- All search results: `adultOk` filters ThePornDB and StashDB results and the `findPerformer` and `findStash` pickers (02, 03).
- Pick handlers: `adultOk` re-checked (03).
- Recommendations: `recEligible` (age >= 18 via `candAge`, female only, and `anySourceMinor`), and `addRecToLibrary` with `adultOk` (04, 34).
- Discover 18–21: `verifyAge` (34).
- Studio: `linked()` excludes `minorRec` performers, applied before any network request (32).
- Sync pull: `minorRec` is checked again (31).
- Calendar birthdays: `minorRec` excluded in 33.
- The TV UI shows an age only if >= 18 (30).
- **Age rules**: `sdAge` takes the worst case, treating a year-only date as 31 Dec and a year-month date as the last day of the month. An unparsable string returns NaN and is rejected. `adultOk` accepts an empty date or a confirmed 18+. `minorRec` is true if a birth date exists and (NaN or under 18).

## 6. Invariants to carry over

1. +18 gate: never weaken it. Incomplete dates are treated as the worst case. It applies before any network request and on every entry path (see section 5).
2. Privacy: all user data stays on the device. No real data, photos or API keys in the repo. API keys and the PIN are excluded from backups (the TV key transfer is opt-in only).
3. Backup and storage formats must remain readable: `{app:'vkte-favorites', v:5, ...}`, the encrypted `vkte-enc` v1, and the auto-backup layout.
4. Schema changes must be backward-compatible. Unknown fields must survive (spread on import).
5. Big new features keep their own DB (as `vkte_studio` does).
6. Never delete on import. Imports update only if the file's `updated` is newer, and otherwise fix missing photos only.
7. Work identity is `wkey(title)|wkey(site)`. Merge rules: fill only empty fields, never remove user data, new works get `a = now`.
8. `save()` is the single write point. After any record change, set `updated = Date.now()`.
9. Sync: the three-way signature comparison, device-local fields (`views`, `lastView`, `nph`) never overwritten, the photo filename pattern, and the lockout rules must be kept for compatibility with an Android TV build.
10. Sanitise all incoming strings: ids against `SAFE_ID`, images against `safeImg`, work URLs must be https.
11. Photos store only a filename on device. Thumbnails regenerate from the first photo. A 30-photo cap per performer.
12. Official sources first (ThePornDB, StashDB, Wikimedia). No scraping and no bypass of protections.
13. TV mode: the page overlays are hidden, the UI is fully focus-driven, and backup and sync client work is off on TV.
14. Honest reporting: Android TV and iPhone behaviour was not testable here.

## Remaining gaps

Please confirm these before the Flutter work depends on them:
- **06-recs**: the whole RecsUI screen.
- **14, 15, 24, 35, 37**: the image reliability, carousel, works UI, motion and UX layers.
- **07**: multi-select, the quick sheet, the previous/next navigator, the merge dialog details, and the list of keyboard shortcuts in 10.
- **11**: the "new release" alert logic.
- **16**: the rest of the VX source (mapping, verify, gather).
- **23**: the Tier half (auto-assign rule from rating).
- **05**: the rest of `wSheet` and `wAddDlg` (lines 660-800), and `toolCompare` and `toolTags` (lines 826-935).
- **30**: TV page bodies (lines 69-273) and the `infoFor` content.
- **04**: lines 509-559 (preview and ignore flow, `recAfterChange`).
- **index.html**: the lbx markup and any other IDs after line 214.
- **app.css**: not opened at all.