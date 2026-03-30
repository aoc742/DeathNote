\# ForgeDMC Toolkit — Module Summary



\*\*21 modules · 4,592 lines · 0 external dependencies · replaces 26 legacy libraries\*\*

\*Version 1.1.0 · Updated 2026-03-21\*



\---



\## The Core Eight — Ace3 Replacements



\---



\### ForgeCore

\*\*v1.0.0 · 291 lines · replaces AceAddon-3.0 + AceEvent-3.0 + AceConsole-3.0\*\*



The spine of the entire toolkit. Every other module either embeds into a ForgeCore addon or integrates with one. `ForgeCore:NewAddon("MyAddon")` creates an addon object with a full lifecycle: `OnInitialize` fires when the addon's saved variables are loaded at `ADDON\_LOADED`, and `OnEnable` fires when the character enters the world at `PLAYER\_LOGIN`. Addons can be divided into named sub-modules via `NewModule`, each with their own identical lifecycle, enabled state, and event subscriptions.



The event system is efficient by design — all addons share a single hidden bootstrap frame rather than each creating their own. Events are only registered with Blizzard when at least one addon is listening, and automatically unregistered when the last listener unsubscribes. `RegisterEvent` accepts either a method name string (`"ZONE\_CHANGED"`) or a bare function, and handlers are dispatched through `pcall` so one bad callback cannot break others.



Chat commands are registered via `RegisterChatCommand("myslash", "OnSlash")` and produce a proper `/myslash` slash command that calls the named method. `Print` and `Printf` write to the default chat frame with the addon name as a coloured prefix. `OpenOptions` integrates directly with ForgeOptions — calling it opens the Settings panel to the addon's registered category.



\---



\### ForgeDB

\*\*v1.1.0 · 201 lines · replaces AceDB-3.0\*\*



Manages SavedVariables storage across three data scopes. The \*\*global\*\* scope is shared account-wide across all characters. The \*\*char\*\* scope is keyed as `"CharacterName-RealmName"` and is unique per character. The \*\*profile\*\* scope is switchable at runtime — multiple named profiles can coexist in the same SavedVariables table and be swapped, copied, or reset without losing the others.



`ForgeDB:New("MyAddonDB", defaults)` bootstraps the raw SavedVariables global, creates all three scope tables, applies default values non-destructively (missing keys only, never overwriting saved data), and returns a proxy object. Reading and writing is direct table access — `self.db.profile.scale = 1.5` — with no metatable overhead per read.



Profile management is a complete API: `SetProfile`, `CopyProfile`, `ResetProfile`, `GetProfiles`, `DeleteProfile`. A callback registered via `RegisterCallback("OnProfileChanged", fn)` fires whenever the active profile changes, which is the hook point for refreshing UI elements after a profile switch.



\---



\### ForgeComm

\*\*v1.1.0 · 223 lines · replaces AceComm-3.0\*\*



Handles addon-to-addon messaging over `C\_ChatInfo.SendAddonMessage`. Registering a prefix is safe to call before `PLAYER\_LOGIN` — prefixes are queued and registered with Blizzard automatically once the player logs in.



`Send` handles short messages under 255 bytes across all channels including WHISPER. `SendChunked` handles payloads of any length by splitting them into 250-byte packets tagged with a `FGC|total|seq|payload` header. The receiver's registered callback fires exactly once with the fully reassembled string — the chunking is completely transparent to both sender and receiver. The incoming assembly buffer is cleaned up immediately after successful delivery to prevent memory accumulation. A warning is printed if the Blizzard session cap of approximately 64 registered prefixes is reached.



\---



\### ForgeHook

\*\*v1.0.0 · 129 lines · replaces AceHook-3.0\*\*



Mixin-style function and script hooking embedded into any object via `ForgeHook:Embed(target)`. Three hook types are supported. Restoreable \*\*method hooks\*\* (`Hook`) replace a table method with a wrapper that calls the original first and then fires the handler — the original is stored and can be fully restored via `Unhook`. \*\*Script hooks\*\* (`HookScript`) work the same way for frame scripts, correctly handling the case where no original script existed. \*\*Secure hooks\*\* (`SecureHook`) use `hooksecurefunc` for post-call appending that cannot cause taint — these are permanent by design and cannot be undone.



All hook state is stored in a weak-keyed table indexed by the hooking object, so if an addon object is abandoned the hooks do not leak memory. `UnhookAll` restores every restoreable hook the object has placed in one call. Handler callbacks accept either a method name string or a bare function.



\---



\### ForgeLocale

\*\*v1.1.0 · 199 lines · replaces AceLocale-3.0\*\*



A locale proxy system for addon string translation. Each language is registered as a separate proxy table — `ForgeLocale:Register("MyAddon", "enUS")` returns a table where you assign translations. Setting `L\["key"] = true` marks that key as using itself as the translation, which is the standard pattern for the English base locale. Setting `L\["key"] = "Translated string"` registers an explicit translation for that language.



`ForgeLocale:Get("MyAddon")` returns the proxy for the current client locale. If the client locale was not registered, it falls back to `enUS`. If `enUS` was not registered, it falls back to the first registered locale. Reading any key that was never translated returns the key string itself rather than `nil` — UI code never needs to guard against nil locale strings. `GetRegisteredLocales`, `IsLocaleRegistered`, and `DumpLocale` are available for tooling and debug.



\---



\### ForgeOptions

\*\*v1.1.0 · 253 lines · replaces AceConfig-3.0 + AceConfigDialog-3.0 + AceConfigRegistry-3.0 + AceDBOptions-3.0\*\*



Builds addon settings panels directly inside Blizzard's native Interface Options window using the Settings API introduced in Dragonflight 10.0. Because the controls are Blizzard-native, they automatically inherit the game's current UI skin, scale, fonts, and keyboard navigation. When Blizzard changes the UI in a future patch, addon settings panels update automatically.



`ForgeOptions:Create("MyAddon", "Panel Title", db)` returns a panel object. `AddCheckbox`, `AddSlider`, and `AddDropdown` add controls tied directly to keys in the passed db table. `AddHeader` adds a non-interactive section label. `CreateSubcategory("Advanced")` creates a child category that appears as a sub-entry in the Settings sidebar. `Register(addon)` finalises the panel and links it to a ForgeCore addon object so `addon:OpenOptions()` works. `Open()` jumps directly to the panel from anywhere in code.



\---



\### ForgeTimer

\*\*v1.1.0 · 242 lines · replaces AceTimer-3.0 + AceBucket-3.0\*\*



Mixin-style timer management embedded via `ForgeTimer:Embed(target)`. All timers are backed by `C\_Timer` rather than `OnUpdate` frame hooks, which is the correct modern approach for WoW addon scheduling.



One-shot timers (`ScheduleTimer`) fire once after a delay. Repeating timers (`ScheduleRepeatingTimer`) tick on an interval. Both return a handle that can be passed to `CancelTimer`. `CancelAllTimers` cancels every timer, debounce, and throttle the object has running in one call.



`Debounce` restarts the delay on every call and fires the callback only once after silence — the right tool for things like search boxes or resize events. `Throttle` fires immediately on the first call and then silently drops all further calls until the interval elapses — the right tool for rate-limiting things like cursor-tracking updates. `CancelDebounce` cancels a pending debounce by key without firing it.



`RegisterBucketEvent` coalesces rapid-fire WoW events — `BAG\_UPDATE` fires dozens of times per loot — into a single batched callback delivered after a short interval. The handler receives the event name and an array of all payloads that arrived during the window.



\---



\### ForgeWidgets

\*\*v1.1.0 · 297 lines · replaces AceGUI-3.0\*\*



Factory functions for common WoW UI elements using Blizzard's own frame templates. Because everything uses native templates, widgets inherit the current UI skin automatically and never look out of place regardless of which client version or UI scale the player is using.



`CreateWindow` makes a movable draggable window registered in `UISpecialFrames` so Escape closes it. `CreatePanel` fills a window with a standard inset content area. `CreateButton`, `CreateCheckBox`, `CreateSlider`, `CreateEditBox`, `CreateScrollFrame` each create their respective native widget. `CreateDropdown` auto-detects The War Within's `DropdownButtonMixin` and uses the modern `WowStyle1DropdownTemplate` on 11.0+ clients, falling back to the legacy template transparently. `CreateTabStrip` creates a horizontal row of tab buttons with active-state highlighting and returns both the frame and a `showTab(index)` function for programmatic control. A `uniqueName()` counter ensures all frame names are globally unique, preventing the crashes that occurred with anonymous nil-named frames.



\---



\## The Extended Thirteen — Common Library Replacements



\---



\### ForgeStub

\*\*v1.0.0 · 117 lines · replaces LibStub\*\*



Solves the version collision problem that LibStub was invented to address: when multiple addons bundle the same shared library file, the newest version should win and older copies should silently stop loading. `ForgeStub:New("MyLib", 5)` returns `nil` if version 5 or higher is already loaded, at which point the caller returns immediately. If the library is new or being upgraded, the existing table is returned so any consumers who already hold a reference see the updated methods.



Unlike LibStub, version metadata is stored in a separate internal registry table rather than inside the library table itself. Library objects are clean Lua tables with no internal bookkeeping fields. `Get`, `GetVersion`, `IsLoaded`, and a sorted `Iterate` complete the API — three query methods that LibStub does not provide.



\---



\### ForgeBabble

\*\*v1.0.0 · 244 lines · replaces LibBabble-Boss-3.0 + LibBabble-Faction-3.0 + LibBabble-SubZone-3.0\*\*



Three legacy libraries consolidated into one file that contains zero static string data. The Babble libraries shipped thousands of hardcoded translation strings for boss names, faction names, and zone names — tens of thousands of string literals loaded into memory on every login regardless of the player's locale, going stale on every patch that changed or added content.



`ForgeBabble.Boss`, `ForgeBabble.Zone`, and `ForgeBabble.Faction` are three sub-modules each with `Get(name)`, `GetByID(id)`, and `FindID(name)` methods. Boss names are pulled from `C\_EncounterJournal` — the same data source the game's own dungeon journal uses, always correct for the current patch and client locale. Zone names come from `C\_Map.GetMapInfo`. Faction names come from `C\_Reputation.GetFactionDataByID`. All results are cached after the first call so repeated lookups are a single table read. `Scan(min, max)` pre-warms the cache for a range of IDs, and `PrintStats()` reports cache hit counts for debugging.



\---



\### ForgeBroker

\*\*v1.0.0 · 426 lines · replaces LibDataBroker-1.1 + LibDBIcon-1.0\*\*



Merges two libraries that were always used together into one self-contained module. LibDataBroker defined a data object standard and LibDBIcon consumed that object to create a minimap button — requiring both plus LibStub and CallbackHandler as prerequisites. ForgeBroker does both jobs without any external dependencies.



`ForgeBroker:Register("MyAddon", dataObject, db)` creates a minimap button immediately. The `dataObject` carries `icon`, `label`, `OnClick`, `OnTooltipShow`, `OnEnter`, and `OnLeave`. The `db` table optionally persists `minimapPos`, `hide`, and `lock` to SavedVariables. Position math handles all fourteen minimap shape variants with correct ellipse and rectangle quadrant calculations. Tooltip anchoring reads the button's screen position and automatically chooses TOP, BOTTOM, LEFT, or RIGHT to avoid clipping off screen. `SetMouseoverOnly` adds a fade-in/out animation so the button stays hidden until the minimap area is hovered. `AddToCompartment` and `RemoveFromCompartment` manage The War Within's AddonCompartment icon tray.



\---



\### ForgeMinimapButton

\*\*v1.0.0 · 523 lines · replaces LibDBIcon-1.0\*\*



A more granular minimap button implementation focused purely on the button rather than merging with a data object concept. Where ForgeBroker is the higher-level API that creates both the data object and the button together, ForgeMinimapButton gives finer visual control over the button independently.



The button uses hardcoded texture IDs matching the standard Blizzard minimap button appearance — the border ring, circular background, and icon slot — making it visually indistinguishable from native WoW minimap buttons. Icon tint is controllable via `iconR/iconG/iconB` on the data object. Boot sequencing delays position updates until `PLAYER\_LOGIN` so any third-party minimap shape addons have loaded first. `Minimap:OnEnter/OnLeave` is hooked globally to coordinate fade-on-hover behaviour across all registered buttons simultaneously. `SetShowOnEnter` enables per-button fade animation. `Refresh` re-reads the db table after a profile switch without re-creating the button.



\---



\### ForgeDialog

\*\*v1.0.0 · 567 lines · replaces LibDialog-1.0\*\*



The most fully-featured module in the toolkit. Provides modal confirmation and input dialogs with a complete widget pooling system — dialog frames, buttons, editboxes, and checkboxes are all recycled rather than created fresh on each spawn, matching LibDialog's performance approach but with cleaner pool state management.



Up to four dialogs can be active simultaneously, stacked vertically below any native Blizzard StaticPopup dialogs via `hooksecurefunc`. Additional spawn calls queue automatically and drain as active dialogs close. The `is\_exclusive` flag dismisses any other exclusive dialog when a new one spawns. The `duration` field sets an auto-cancel timeout. `hide\_on\_escape` dismisses on the Escape key via `StaticPopup\_EscapePressed` hook. Dialogs support multiple editboxes with labels, placeholder text, `on\_enter\_pressed` and `on\_text\_changed` callbacks, and multiple checkboxes with `get\_value`/`set\_value` state callbacks. `Spawn` accepts either a registered name string or an inline delegate table for one-off dialogs.



\---



\### ForgeGeo

\*\*v1.0.0 · 79 lines · replaces HereBeDragons\*\*



Map coordinate and distance calculations built entirely on Blizzard's modern C\_Map API. HereBeDragons maintained large internal tables of map transformation data to handle the complex coordinate space conversions that existed in older WoW versions. Since the map system was rebuilt, `C\_Map` handles all of this natively in C++.



`GetPlayerMapPosition` and `GetUnitMapPosition` return normalised x/y coordinates between 0.0 and 1.0 via `C\_Map.GetPlayerMapPosition`. `GetUnitWorldPosition` uses `UnitPosition` to get actual yard-scale world coordinates and instance ID. `WorldDistance` calculates true 3D Euclidean distance between any two units in yards — the unit used for spell range checks — via `UnitPosition`. `IsUnitNearby(unit, yards)` is a one-call convenience wrapper. `GetMapChildren` retrieves sub-zone information for a given map ID.



\---



\### ForgeGlow

\*\*v1.0.0 · 155 lines · replaces LibCustomGlow\*\*



Animated pixel-border glow effects for any WoW frame. `ShowGlow` places a configurable number of coloured texture segments evenly around the perimeter of a frame and pulses their alpha via a `C\_Timer` sine wave loop. All texture objects are drawn from a shared pool and returned to it on `HideGlow`, so repeated show/hide cycles generate no garbage. `SetGlowColor` changes the colour of an active glow in place without restarting the animation.



Three presets cover the most common use cases without requiring any parameters: `ShowActionGlow` produces a gold pulse used for ability proc alerts, `ShowInventoryGlow` produces a blue highlight used for item attention, and `ShowQuestGlow` produces a green pulse for quest-relevant targets. Frames that are zero-sized when `ShowGlow` is called are handled gracefully — the glow defers via `C\_Timer.After(0)` until the frame has dimensions before placing textures.



\---



\### ForgeMedia

\*\*v1.0.0 · 67 lines · replaces LibSharedMedia-3.0\*\*



A shared registry that maps human-readable names to file paths for fonts, statusbar textures, sounds, borders, and backgrounds. Any addon can register its assets once and any other addon can retrieve them by name without needing to know the file path. Ships with the five standard WoW fonts and two statusbar textures pre-registered so basic usage needs no additional registration.



`Register(type, name, path)` adds a new entry. `Fetch(type, name)` retrieves the path. `List(type)` returns the full bucket table. `HashList(type)` returns a sorted array of registered names suitable for dropdown population. `Exists(type, name)` is a boolean availability check. Media type strings are normalised to lowercase so `"Font"` and `"font"` are treated identically. Any string is accepted as a media type — the registry is not limited to the five built-in categories.



\---



\### ForgePacker

\*\*v1.0.0 · 125 lines · replaces LibDeflate serialisation layer + AceSerializer\*\*



Serialises Lua tables to and from a compact delimiter-separated string format for transmission over addon messages or storage in SavedVariables. Handles all Lua primitives: `nil`, `boolean`, `number`, `string` (with escape sequences for delimiter characters), and nested tables via recursive `NEST\_OPEN`/`NEST\_CLOSE` markers. Integer keys are tagged with a prefix byte to distinguish them from string keys, so array-style tables round-trip correctly.



`ForgePacker.Pack(tbl)` returns a string. `ForgePacker.Unpack(str)` returns a table. `PackArray` and `UnpackArray` are convenience wrappers that work with numerically-indexed tables only. The format is deliberately human-readable in a debugger — during development you can read the raw packed string and understand its contents without a decoder. Unlike LibDeflate, there is no binary compression. This is appropriate for small-to-medium payloads; for large data structures a compression codec would produce shorter strings.



\---



\### ForgeQueue

\*\*v1.0.0 · 107 lines · replaces ChatThrottleLib\*\*



A throttled message queue that prevents addon-to-player disconnects from sending too many chat or addon messages in a short window. Messages are enqueued rather than sent immediately and dispatched one at a time on a 0.5-second `C\_Timer` interval.



Three priority lanes handle urgency differentiation — `HIGH`, `NORMAL`, and `LOW`. High-priority messages always drain before normal, normal before low. `SendAddonMessage` and `SendChatMessage` are convenience wrappers for the two most common use cases; `Enqueue(fn, priority, ...)` accepts any function for other message types. `Flush()` sends everything immediately for use during logout. `Clear(priority)` empties one lane or all lanes. `GetQueueSize()` returns total count plus a per-lane breakdown. `SetThrottle(seconds)` adjusts the send rate for situations requiring tighter or looser pacing. The queue silently drops new entries when it reaches 512 to prevent unbounded memory growth.



\---



\### ForgeRange

\*\*v1.0.0 · 95 lines · replaces LibRangeCheck\*\*



Unit range checking via spell and item probes. Because WoW does not expose a direct API for yard distance to arbitrary units, range checking has always worked by probing whether specific spells or items are in range — the known range of those spells then brackets where the unit must be.



`IsSpellInRange(unit, spellID)` and `IsItemInRange(unit, itemID)` are direct wrappers around `C\_Spell.IsSpellInRange` and `IsItemInRange`. `GetMinRange(unit)` tries each registered probe spell in ascending yard order and returns the smallest yard value that reports in-range. `GetRangeBracket(unit)` maps that result to a named string — Melee, Short, Medium, Long, Max Spell, or Extreme — plus the numeric yard value. Default probes cover 10, 30, and 40 yards. `RegisterProbeSpell` and `RegisterProbeItem` allow any addon to add custom probes for their specific class or spec, extending the bracket resolution without modifying the module.



\---



\### ForgeSkin

\*\*v1.0.0 · 133 lines · replaces Masque\*\*



A dark flat UI theme applied to individual frames and widgets. Uses a 1-pixel solid border backdrop built from `WHITE8X8` textures with configurable RGBA colour values stored in `ForgeSkin.theme`. Unlike Masque — which is a full skinning framework designed to restyle any addon's action buttons — ForgeSkin is scoped to your own addon's frames and gives you complete, direct control over exactly how they look.



`SkinButton` strips all default Blizzard button textures, applies the dark backdrop, adds a custom highlight overlay, and hooks `OnMouseDown/OnMouseUp` to darken on press. `SkinEditBox` hides the default multi-part border textures and replaces them with the flat backdrop. `SkinScrollFrame` skins the frame and colours the scroll thumb. `SkinCheckButton` applies the dark backdrop to checkboxes. `SkinAll(frame, true)` recurses through all children of a frame and applies the appropriate skin function based on each child's object type. `SetTheme(overrides)` accepts a partial table of RGBA overrides so individual colours can be changed without redefining the entire theme.



\---



\### ForgeWindow

\*\*v1.0.0 · 119 lines · replaces LibWindow\*\*



Frame position and scale persistence via SavedVariables. `ForgeWindow:Register(frame, key, db, defaults)` links a frame to a db table key, restores any previously saved position and scale immediately, and hooks `OnDragStart/OnDragStop` to auto-save whenever the player moves the frame. No manual save call is needed from addon code — moving the frame is the save trigger.



`Save(key)` captures the frame's current anchor point, x, y offset, and scale via `GetPoint(1)` and `GetScale()`. `Restore(key)` applies the saved values with scale clamped between 0.4 and 2.5 to prevent frames from becoming invisible. `Reset(key)` restores to the defaults passed at registration. `ResetAll()` resets every registered frame in one call. `Clamp(key)` enables `SetClampedToScreen` so the frame cannot be dragged off screen. `GetPosition(key)` returns all five saved values for inspection. The drag hook is guarded by a `\_fwDragHooked` flag so calling `Register` multiple times on the same frame never double-hooks it.



\---



\## Quick Reference



| Module | Lines | Replaces | Key API |

|---|---|---|---|

| ForgeCore | 291 | AceAddon · AceEvent · AceConsole | `NewAddon` · `RegisterEvent` · `RegisterChatCommand` · `Print` |

| ForgeDB | 201 | AceDB-3.0 | `New` · `SetProfile` · `ResetProfile` · `CopyProfile` |

| ForgeComm | 223 | AceComm-3.0 | `Register` · `Send` · `SendChunked` · `Unregister` |

| ForgeHook | 129 | AceHook-3.0 | `Hook` · `HookScript` · `SecureHook` · `Unhook` · `UnhookAll` |

| ForgeLocale | 199 | AceLocale-3.0 | `Register` · `Get` · `GetRegisteredLocales` |

| ForgeOptions | 253 | AceConfig × 4 | `Create` · `AddCheckbox` · `AddSlider` · `AddDropdown` · `Register` |

| ForgeTimer | 242 | AceTimer · AceBucket | `ScheduleTimer` · `Debounce` · `Throttle` · `RegisterBucketEvent` |

| ForgeWidgets | 297 | AceGUI-3.0 | `CreateWindow` · `CreateButton` · `CreateSlider` · `CreateTabStrip` |

| ForgeStub | 117 | LibStub | `New` · `Get` · `GetVersion` · `IsLoaded` · `Iterate` |

| ForgeBabble | 244 | LibBabble × 3 | `Boss:GetByID` · `Zone:GetByMapID` · `Faction:GetByID` |

| ForgeBroker | 426 | LibDataBroker · LibDBIcon | `Register` · `Show` · `Hide` · `Lock` · `AddToCompartment` |

| ForgeMinimapButton | 523 | LibDBIcon-1.0 | `Register` · `Show` · `Hide` · `SetShowOnEnter` · `Refresh` |

| ForgeDialog | 567 | LibDialog-1.0 | `Register` · `Spawn` · `Dismiss` · `DismissAll` · `IsActive` |

| ForgeGeo | 79 | HereBeDragons | `GetPlayerMapPosition` · `WorldDistance` · `IsUnitNearby` |

| ForgeGlow | 155 | LibCustomGlow | `ShowGlow` · `HideGlow` · `ShowActionGlow` · `ShowQuestGlow` |

| ForgeMedia | 67 | LibSharedMedia-3.0 | `Register` · `Fetch` · `List` · `HashList` · `Exists` |

| ForgePacker | 125 | LibDeflate · AceSerializer | `Pack` · `Unpack` · `PackArray` · `UnpackArray` |

| ForgeQueue | 107 | ChatThrottleLib | `Enqueue` · `SendAddonMessage` · `Flush` · `Clear` · `SetThrottle` |

| ForgeRange | 95 | LibRangeCheck | `GetMinRange` · `GetRangeBracket` · `RegisterProbeSpell` |

| ForgeSkin | 133 | Masque | `SkinButton` · `SkinFrame` · `SkinAll` · `SetTheme` |

| ForgeWindow | 119 | LibWindow | `Register` · `Save` · `Restore` · `Reset` · `Clamp` |



