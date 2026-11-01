# Your pets have a home

The current Mac source build saves every imported sprite pack in a local pet library. **Add your dog…**, **Import pet…**, and `lokidot dog FOLDER` validate the pack, save their own copy, and select it. You can move the original folder afterward; keeping it as a backup is still useful.

Open **Saved pets…** in the playground or paw menu, or run `lokidot pets`.

| Control | What it does |
| --- | --- |
| **Load pet** | Makes a saved pet available and shows it on the desktop. Loaded pets also join **The whole pack**. |
| **Unload pet** | Removes that import from the loaded pack. Its saved files remain. It stays unloaded after restarting Zoomies. |
| **Remove saved copy…** | Asks before moving the managed copy to macOS Trash. It never removes the original import folder. |
| **Put pets away** / `lokidot unload` | Hides all pets, including the bundled dogs, without deleting any packs. The hidden state survives a restart. |
| **Let’s go!** / `lokidot resume` | Brings the chosen loaded pet or pack back. Use Load pet first for an unloaded import. |

The app remembers the last selected pet or whole-pack setting. It loads saved imports at startup unless you unloaded them. If you unload the only selected pet, the desktop clears until you choose another. The bundled dogs stay part of the app; Put pets away hides them.

## Saved copies and originals

For the standard app, managed copies live under:

```text
~/Library/Application Support/com.ashrocket.LokiDotZoomies/ImportedPets/
```

Each saved pet contains only a validated `manifest.json` and `atlas.png`. Reference photos, agent notes, and other files in the source folder are not copied. Personal packs are not included in source control or installers. App updates preserve this library.

Importing the exact same pack again reuses its saved copy and loads it. Different artwork stays separate even when both manifests use the same name or ID. The original manifest ID never replaces a bundled dog. Saved imports have their own local identifiers; hover over a name in Saved pets to see its identifier.

The previous Mac import flow remembered only one external folder. This build migrates that remembered pack to a saved copy on launch if the original folder is still available. A missing original is reported; import it again from its current location. No source folder is deleted during migration.

## Recover a pet

- **Unloaded:** select it in Saved pets and click Load pet.
- **Removed:** import the original folder again, or restore the saved folder from Trash before reopening the app.
- **Needs repair:** other saved pets still load. Keep a backup, remove the damaged managed copy through Saved pets, then import a complete pack again. Reimport does not silently overwrite damaged data.

Published 1.3.2 downloads and the Windows preview retain their earlier import behavior; keep their original folders in place. Calendar and library changes are currently available in the Mac source build.
