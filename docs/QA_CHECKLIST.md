# QA checklist (brief §19)

Status: ✅ verified (with evidence), ⚠️ partly verified, ❌ not verified / not implemented.

## Gameplay
| Check | Status | Evidence |
|-------|--------|----------|
| Complete races can be played | ✅ | 3-lap Helix Bay race with 7 AI finished (headless); 1-lap race to the results screen on the A56 |
| Player can finish full circuits | ✅ | Autopilot laps of Helix Bay and the Proving Ground. Human play: ❌ not yet |
| Handling consistent | ✅ | Determinism test; handling bench |
| Airbrakes function independently | ✅ | `test_single_airbrake_yaws_and_is_symmetric`, `test_airbrake_tightens_a_full_lock_turn` |
| Physics stable | ✅ | Hover settle, banked-oval and jump tests; step-size robustness |
| No major track collision bugs | ⚠️ | Analytic floor and walls tested; minimum hull height in full races 0.95–0.99 m. Not yet checked: every section of every track by a human |
| Respawn works | ✅ | `test_respawn_returns_to_last_safe_point`; every ship gets a safety respawn when outside the track envelope (`Race._safety_respawn`); wedged or wrong-way AI recover |

## AI
| Check | Status | Evidence |
|-------|--------|----------|
| Opponents complete races | ✅ | All 7 AI in every logged race |
| Opponents overtake | ✅ | Position changes in telemetry; pass-side logic in `AIDriver._traffic` |
| Opponents use weapons | ✅ | 3-lap race: 14 pickups, 13 shots by AI and the autopilot, 12 hits (plasma, EMP, mines, shockwave); `test_weapons.gd` (7 tests) |
| Difficulty settings work | ✅ | ROOKIE best laps 91–98 s vs PRO 83–88 s |

## Graphics
| Check | Status | Evidence |
|-------|--------|----------|
| No major clipping / broken materials / missing textures | ⚠️ | Screenshot passes on desktop and the A56. A tunnel interior bug and a cockpit spine were found and fixed. Not every camera on every section has been reviewed |
| Stable rendering | ✅ | No render errors in device logcat |

## Android
| Check | Status | Evidence |
|-------|--------|----------|
| Successful installation | ✅ | A56 (Android 17) and the Android 15 emulator |
| Successful startup | ✅ | A56: menus, race, results. Emulator: engine starts but cannot present Vulkan frames |
| Responsive controls | ❌ | Touch and tilt implemented; not yet tried by a person on the phone |
| Correct screen scaling | ⚠️ | 2340×1080 (A56) and 1280×720 desktop. No other aspect ratios tested |
| Stable frame pacing | ⚠️ | Mean 58 fps, dips to 35–55 near the Helix (see PERFORMANCE.md) |
| No critical crashes | ✅ | None observed (one device session, many desktop runs) |

## Systems
| Check | Status | Evidence |
|-------|--------|----------|
| Menus work | ✅ | Menu screenshots; full flow on the A56 |
| Settings persist | ⚠️ | ConfigFile save/load code. No automated test |
| Saves persist | ✅ | `test_save.gd` (round trip, tamper rejection, records); results booked on the A56 |
| Audio works | ✅ | `gen_audio.py --check` passes for all 44 files; in-game bus peaks −4 to −15 dB |
| Race results recorded | ✅ | Results screen showed "new lap record" and credits on the A56 |

## Modes and progression (brief §15)
| Check | Status | Evidence |
|-------|--------|----------|
| Single Race, Elimination, Combat, Speed Challenge, Time Trial, Practice | ✅ | Each run headless to the results screen; `test_modes.gd` (knockout order, combat ranking, medals) |
| Career objectives and rewards | ✅ | `--career=s1` / `s2`: objective met, reward booked once |
| Championship | ✅ | `--cup=bay_open`, 3 rounds: points accumulated, cup completed, standings correct |
| Credits cannot be farmed in solo modes | ✅ | `test_book_race_records_best_lap` (speed pays by medal, time trial pays nothing) |
| Unlocks (teams and classes by credits) | ⚠️ | Rule implemented in the menus; no automated test |
| Mode balance (AI pace, item odds) | ❌ | Tuned only with AI-versus-AI races; the Meridian "risk" pilot wins often |
